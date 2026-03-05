defmodule JargaAdmin.Quecto.Bridge do
  @moduledoc """
  GenServer that manages a Quecto agent process for commerce store management.

  Spawns the `quecto` binary with a commerce system prompt, forwards user
  messages via stdin (JSON-line protocol), and streams responses back via
  Phoenix PubSub so LiveViews can subscribe.

  ## Configuration
  - `QUECTO_BIN`      — path to quecto binary (default: "quecto")
  - `QUECTO_BASE_DIR` — working directory for quecto (default: CWD)

  ## PubSub topics
  - `"quecto:<session_id>:response"` — streamed response chunks
  - `"quecto:<session_id>:activity"` — agent activity events (tool calls, etc.)
  - `"quecto:<session_id>:done"`     — response finished
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub

  @registry JargaAdmin.Quecto.Registry
  @pubsub JargaAdmin.PubSub

  defstruct [
    :session_id,
    :port,
    :status,
    :buffer,
    :pending_response
  ]

  # ──────────────────────────────────────────────────────────────────────────
  # Client API
  # ──────────────────────────────────────────────────────────────────────────

  @doc "Start a bridge for a given session."
  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  @doc "Send a user message; response streams back via PubSub."
  def send_message(session_id, message) do
    GenServer.call(via(session_id), {:send_message, message}, 60_000)
  end

  @doc "Check if the bridge process is alive and ready."
  def alive?(session_id) do
    case Registry.lookup(@registry, session_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  @doc "Get or start a bridge for the given session."
  def ensure_started(session_id) do
    case Registry.lookup(@registry, session_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        DynamicSupervisor.start_child(
          JargaAdmin.Quecto.Supervisor,
          {__MODULE__, session_id: session_id}
        )
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # GenServer callbacks
  # ──────────────────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)

    state = %__MODULE__{
      session_id: session_id,
      port: nil,
      status: :starting,
      buffer: "",
      pending_response: nil
    }

    {:ok, state, {:continue, :start_process}}
  end

  @impl true
  def handle_continue(:start_process, state) do
    case open_port(state.session_id) do
      {:ok, port} ->
        {:noreply, %{state | port: port, status: :ready}}

      {:error, reason} ->
        Logger.error("Quecto bridge failed to start: #{inspect(reason)}")
        {:noreply, %{state | status: :unavailable}}
    end
  end

  @impl true
  def handle_call({:send_message, _message}, _from, %{status: :unavailable} = state) do
    {:reply, {:error, :quecto_unavailable}, state}
  end

  @impl true
  def handle_call({:send_message, message}, from, %{port: port} = state) when not is_nil(port) do
    payload = Jason.encode!(%{type: "message", content: message}) <> "\n"

    try do
      Port.command(port, payload)
      {:noreply, %{state | pending_response: from}}
    rescue
      e ->
        Logger.error("Failed to send to quecto: #{inspect(e)}")
        {:reply, {:error, :send_failed}, state}
    end
  end

  @impl true
  def handle_call({:send_message, message}, from, %{status: :starting} = state) do
    # Queue – retry after process starts
    Process.send_after(self(), {:retry_send, message, from}, 500)
    {:noreply, state}
  end

  @impl true
  def handle_info({:retry_send, message, from}, state) do
    handle_call({:send_message, message}, from, state)
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    new_buffer = state.buffer <> data
    {lines, remaining} = split_lines(new_buffer)

    new_state = Enum.reduce(lines, %{state | buffer: remaining}, &process_line/2)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("Quecto process exited with status #{status}, restarting...")
    Process.send_after(self(), :restart, 2_000)
    {:noreply, %{state | port: nil, status: :restarting}}
  end

  @impl true
  def handle_info(:restart, state) do
    case open_port(state.session_id) do
      {:ok, port} ->
        {:noreply, %{state | port: port, status: :ready}}

      {:error, reason} ->
        Logger.error("Quecto restart failed: #{inspect(reason)}")
        Process.send_after(self(), :restart, 5_000)
        {:noreply, %{state | status: :restarting}}
    end
  end

  @impl true
  def handle_info({port, :closed}, %{port: port} = state) do
    Logger.info("Quecto port closed")
    {:noreply, %{state | port: nil, status: :stopped}}
  end

  @impl true
  def terminate(_reason, %{port: port}) when not is_nil(port) do
    Port.close(port)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # ──────────────────────────────────────────────────────────────────────────
  # Private helpers
  # ──────────────────────────────────────────────────────────────────────────

  defp via(session_id) do
    {:via, Registry, {@registry, session_id}}
  end

  defp open_port(session_id) do
    quecto_bin = System.get_env("QUECTO_BIN") || "quecto"
    base_dir = System.get_env("QUECTO_BASE_DIR") || File.cwd!()
    system_prompt = commerce_system_prompt()

    # Write system prompt to a temp file
    prompt_path = Path.join(System.tmp_dir!(), "jarga_system_#{session_id}.md")
    File.write!(prompt_path, system_prompt)

    args = [
      "agent",
      "--interactive",
      "--system-prompt-file",
      prompt_path,
      "--output-format",
      "jsonl"
    ]

    try do
      port =
        Port.open({:spawn_executable, System.find_executable(quecto_bin) || quecto_bin}, [
          {:args, args},
          {:cd, base_dir},
          :binary,
          :use_stdio,
          :stderr_to_stdout,
          {:exit_status, true},
          {:env,
           [
             {~c"JARGA_API_URL",
              to_charlist(System.get_env("JARGA_API_URL", "http://localhost:3000"))},
             {~c"JARGA_API_KEY", to_charlist(System.get_env("JARGA_API_KEY", ""))}
           ]}
        ])

      {:ok, port}
    rescue
      e ->
        Logger.warning("Quecto binary not found (#{inspect(e)}), running in mock mode")
        {:error, :binary_not_found}
    end
  end

  defp split_lines(buffer) do
    lines = String.split(buffer, "\n")
    complete = Enum.slice(lines, 0..-2//1)
    remaining = List.last(lines) || ""
    {Enum.filter(complete, &(&1 != "")), remaining}
  end

  defp process_line(line, state) do
    case Jason.decode(line) do
      {:ok, event} ->
        handle_event(event, state)

      {:error, _} ->
        # Plain text chunk — treat as response text
        broadcast_chunk(state.session_id, line)
        state
    end
  end

  defp handle_event(%{"type" => "text", "content" => text}, state) do
    broadcast_chunk(state.session_id, text)
    state
  end

  defp handle_event(%{"type" => "tool_start"} = event, state) do
    broadcast_activity(state.session_id, %{
      kind: :tool_started,
      tool: event["name"],
      args: summarise_args(event["args"]),
      time: current_time()
    })

    state
  end

  defp handle_event(%{"type" => "tool_end"} = event, state) do
    broadcast_activity(state.session_id, %{
      kind: :tool_finished,
      tool: event["name"],
      duration_ms: event["duration_ms"],
      time: current_time()
    })

    state
  end

  defp handle_event(%{"type" => "thinking"} = event, state) do
    broadcast_activity(state.session_id, %{
      kind: :thinking,
      model: event["model"],
      tokens: event["tokens"],
      time: current_time()
    })

    state
  end

  defp handle_event(%{"type" => "approval_needed"} = event, state) do
    id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

    broadcast_activity(state.session_id, %{
      kind: :awaiting_approval,
      id: id,
      description: event["description"],
      time: current_time()
    })

    state
  end

  defp handle_event(%{"type" => "done"}, state) do
    broadcast_done(state.session_id)

    if state.pending_response do
      GenServer.reply(state.pending_response, :ok)
    end

    %{state | pending_response: nil}
  end

  defp handle_event(%{"type" => "ui_spec", "spec" => spec}, state) do
    PubSub.broadcast(@pubsub, "quecto:#{state.session_id}:ui_spec", {:ui_spec, spec})
    state
  end

  defp handle_event(event, state) do
    Logger.debug("Quecto unknown event: #{inspect(event)}")
    state
  end

  defp broadcast_chunk(session_id, text) do
    PubSub.broadcast(@pubsub, "quecto:#{session_id}:response", {:chunk, text})
  end

  defp broadcast_activity(session_id, event) do
    PubSub.broadcast(@pubsub, "quecto:#{session_id}:activity", {:activity, event})
  end

  defp broadcast_done(session_id) do
    PubSub.broadcast(@pubsub, "quecto:#{session_id}:response", :done)
  end

  defp summarise_args(nil), do: nil

  defp summarise_args(args) when is_map(args) do
    args
    |> Map.take(~w(query filter limit id))
    |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)
    |> Enum.join(", ")
  end

  defp summarise_args(_), do: nil

  defp current_time do
    DateTime.utc_now() |> Calendar.strftime("%H:%M:%S")
  end

  defp commerce_system_prompt do
    """
    You are the Jarga Commerce AI agent — a store manager assistant with full access
    to all Jarga Commerce API modules: Products, Orders, Customers, Basket, Checkout,
    Promotions, and Storefront.

    ## Your role
    - Help the merchant understand and manage their store
    - Take actions via the available API tools
    - Provide clear, concise answers with real data
    - Proactively identify issues (low stock, pending orders, etc.)

    ## UI Specs
    When displaying data, include a structured UI spec in your response using this format:

    ```json
    {"ui": {"layout": "full", "components": [
      {"type": "metric_card", "title": "Revenue", "data": {"value": "£1,234", "trend": 12.5}},
      {"type": "data_table", "title": "Recent Orders", "data": {"columns": [...], "rows": [...]}},
      {"type": "detail_card", "title": "Order #123", "data": {"pairs": [...], "timeline": [...]}}
    ]}}
    ```

    ## Component types
    - `metric_card`: {label, value, trend (%), subtitle}
    - `data_table`: {columns: [{key, label, type?}], rows: [...], title}
    - `detail_card`: {title, pairs: [{label, value, type?}], timeline: [{title, time}], actions?}
    - `chart`: {type: line|bar|doughnut, title, labels: [...], datasets: [{label, data: [...]}]}
    - `alert_banner`: {kind: info|warn|error, title?, message}
    - `dynamic_form`: {title, fields: [{key, label, type, required?, options?, placeholder?}]}
    - `empty_state`: {icon?, title, message?}

    ## Available API tools (call via HTTP to the Jarga API):

    ### Products (PIM)
    - list_products(page?, per_page?, status?, search?) → GET /v1/pim/products
    - get_product(id) → GET /v1/pim/products/:id
    - create_product(name, description, price, status, sku?) → POST /v1/pim/products
    - update_product(id, attrs) → PUT /v1/pim/products/:id
    - delete_product(id) → DELETE /v1/pim/products/:id

    ### Orders (OMS)
    - list_orders(page?, per_page?, status?, from_date?, to_date?) → GET /v1/oms/orders
    - get_order(id) → GET /v1/oms/orders/:id
    - update_order_status(id, status) → PUT /v1/oms/orders/:id/status
    - process_refund(id, amount?, reason?) → POST /v1/oms/orders/:id/refund

    ### Customers (CRM)
    - list_customers(page?, per_page?, search?, tag?) → GET /v1/crm/customers
    - get_customer(id) → GET /v1/crm/customers/:id

    ### Inventory
    - get_inventory_levels(product_id?) → GET /v1/inventory/levels
    - update_inventory(product_id, quantity) → PUT /v1/inventory/:product_id

    ### Promotions
    - list_promotions() → GET /v1/promotions/campaigns
    - create_promotion(name, type, value, conditions?) → POST /v1/promotions/campaigns
    - update_promotion(id, attrs) → PUT /v1/promotions/campaigns/:id

    ### Analytics
    - get_sales_analytics(period?, from_date?, to_date?) → GET /v1/analytics/sales
    - get_product_analytics(period?) → GET /v1/analytics/products

    ### Store context
    - get_agent_context() → GET /v1/agent/context (full store snapshot)

    ## Guidelines
    - Always fetch real data before making claims about store metrics
    - Ask for confirmation before destructive actions (delete, refund)
    - Keep responses concise — merchants are busy
    - Surface important issues proactively (low stock, unpaid orders)
    - Format money as £X,XXX.XX
    - Format dates as "DD Mon YYYY"
    """
  end
end
