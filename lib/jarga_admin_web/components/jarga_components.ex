defmodule JargaAdminWeb.JargaComponents do
  @moduledoc """
  Jarga Admin UI components — cinematic design system.

  Covers: DataTable, MetricCard, DetailCard, DynamicForm,
          AlertBanner, EmptyState, ActivityFeed, Chart
  """
  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]

  # ──────────────────────────────────────────────────────────────────────────
  # DataTable (Issue #21)
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Renders a sortable, filterable data table with the cinematic card style.

  ## Examples

      <.data_table
        id="orders-table"
        title="Recent Orders"
        columns={[
          %{key: :id, label: "Order"},
          %{key: :customer, label: "Customer"},
          %{key: :total, label: "Total"},
          %{key: :status, label: "Status"}
        ]}
        rows={@orders}
        sort_key={@sort_key}
        sort_dir={@sort_dir}
        on_sort="sort"
        actions={[%{label: "View", event: "view_order"}]}
      />
  """
  attr :id, :string, required: true
  attr :title, :string, default: nil
  attr :columns, :list, required: true
  attr :rows, :list, required: true
  attr :sort_key, :atom, default: nil
  attr :sort_dir, :atom, default: :asc
  attr :on_sort, :string, default: nil
  attr :on_row_click, :string, default: nil
  attr :actions, :list, default: []
  attr :empty_message, :string, default: "No data to display"

  def data_table(assigns) do
    ~H"""
    <div class="j-card" id={@id}>
      <div style="padding:20px 20px 0;">
        <h2 :if={@title} class="j-card-title">{@title}</h2>
      </div>
      <div :if={@rows == []} class="j-empty-state">
        <p class="j-empty-text">{@empty_message}</p>
      </div>
      <div :if={@rows != []} class="j-table-wrap">
        <table class="j-table">
          <thead>
            <tr>
              <th
                :for={col <- @columns}
                phx-click={@on_sort && @on_sort}
                phx-value-key={col[:key]}
                style={if @on_sort, do: "cursor:pointer", else: ""}
              >
                {col[:label]}
                <span :if={@sort_key == col[:key]}>
                  {if @sort_dir == :asc, do: " ↑", else: " ↓"}
                </span>
              </th>
              <th :if={@actions != []}>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={row <- @rows}
              phx-click={@on_row_click}
              phx-value-id={@on_row_click && row_id(row)}
              style={if @on_row_click, do: "cursor:pointer;", else: ""}
            >
              <td :for={col <- @columns}>
                {render_cell(row, col)}
              </td>
              <td :if={@actions != []}>
                <div style="display:flex;gap:8px;flex-wrap:wrap;">
                  <button
                    :for={action <- @actions}
                    class="j-btn j-btn-ghost j-btn-sm"
                    phx-click={action[:event] || action["event"]}
                    phx-value-id={row_id(row)}
                  >
                    {action[:label] || action["label"]}
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp render_cell(row, col) when is_map(row) do
    key = col[:key]
    val = Map.get(row, key) || Map.get(row, to_string(key))

    case col[:type] do
      :status -> render_status(val)
      :money -> format_money(val)
      _ -> to_string(val || "—")
    end
  end

  defp render_cell(row, col) when is_list(row) do
    val = Keyword.get(row, col[:key])
    to_string(val || "—")
  end

  defp row_id(row) when is_map(row), do: to_string(Map.get(row, :id) || Map.get(row, "id") || "")
  defp row_id(_), do: ""

  defp render_status(nil), do: ""

  defp render_status(status) do
    {css, label} =
      case to_string(status) do
        s when s in ["active", "fulfilled", "published", "paid"] ->
          {"j-badge j-badge-green", s}

        s when s in ["cancelled", "refunded", "archived", "failed"] ->
          {"j-badge j-badge-red", s}

        s when s in ["pending", "draft", "processing"] ->
          {"j-badge j-badge-amber", s}

        s ->
          {"j-badge j-badge-muted", s}
      end

    raw(~s(<span class="#{css}">#{label}</span>))
  end

  defp format_money(nil), do: "—"

  defp format_money(val) when is_number(val),
    do: "£#{:erlang.float_to_binary(val / 1, decimals: 2)}"

  defp format_money(val), do: to_string(val)

  # ──────────────────────────────────────────────────────────────────────────
  # MetricCard (Issue #22)
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Renders a KPI metric card.

  ## Examples

      <.metric_card
        label="Revenue"
        value="£12,450"
        trend={+12.4}
        subtitle="Today vs yesterday"
      />
  """
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :trend, :float, default: nil
  attr :subtitle, :string, default: nil

  def metric_card(assigns) do
    ~H"""
    <div class="j-card" style="padding:20px 24px;">
      <p class="j-eyebrow" style="margin-bottom:10px;">{@label}</p>
      <p class="j-metric-value">{@value}</p>
      <div
        :if={@trend != nil}
        style="margin-top:8px;font-family:'Manrope',sans-serif;font-size:0.85rem;"
      >
        <span class={if @trend >= 0, do: "j-trend-up", else: "j-trend-down"}>
          {if @trend >= 0, do: "▲", else: "▼"} {abs(@trend)}%
        </span>
      </div>
      <p :if={@subtitle} style="margin-top:6px;font-size:0.85rem;color:var(--text-muted);">
        {@subtitle}
      </p>
    </div>
    """
  end

  @doc """
  Renders a grid of metric cards.
  """
  attr :metrics, :list, required: true

  def metric_grid(assigns) do
    ~H"""
    <div class="j-metric-grid">
      <.metric_card
        :for={m <- @metrics}
        label={m[:label] || m["label"]}
        value={m[:value] || m["value"]}
        trend={m[:trend] || m["trend"]}
        subtitle={m[:subtitle] || m["subtitle"]}
      />
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # DetailCard (Issue #22)
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Renders an entity detail card with key-value pairs and optional timeline.

  ## Examples

      <.detail_card
        title="Order #1234"
        pairs={[
          %{label: "Customer", value: "Sarah Mitchell"},
          %{label: "Status", value: "fulfilled", type: :status},
          %{label: "Total", value: "£89.00"}
        ]}
        timeline={[
          %{title: "Order placed", time: "2 Mar 14:32"},
          %{title: "Payment confirmed", time: "2 Mar 14:33"},
          %{title: "Dispatched", time: "3 Mar 09:12"}
        ]}
        actions={[%{label: "Process Refund", event: "refund"}]}
      />
  """
  attr :title, :string, required: true
  attr :pairs, :list, default: []
  attr :timeline, :list, default: []
  attr :actions, :list, default: []

  def detail_card(assigns) do
    ~H"""
    <div class="j-card" style="padding:24px;">
      <h2 class="j-card-title">{@title}</h2>

      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:16px;margin-bottom:20px;">
        <div :for={pair <- @pairs}>
          <p class="j-eyebrow" style="margin-bottom:4px;">{pair[:label] || pair["label"]}</p>
          <div :if={(pair[:type] || pair["type"]) == :status}>
            {render_status(pair[:value] || pair["value"])}
          </div>
          <p
            :if={(pair[:type] || pair["type"]) != :status}
            style="font-family:'Manrope',sans-serif;font-size:0.9rem;color:var(--text-primary);"
          >
            {pair[:value] || pair["value"]}
          </p>
        </div>
      </div>

      <div :if={@timeline != []} style="margin-top:20px;">
        <p class="text-label" style="margin-bottom:12px;">Timeline</p>
        <div class="j-timeline">
          <div :for={event <- @timeline} class="j-timeline-item">
            <div class="j-timeline-dot">●</div>
            <div class="j-timeline-content">
              <p class="j-timeline-title">{event[:title] || event["title"]}</p>
              <p class="j-timeline-time">{event[:time] || event["time"]}</p>
            </div>
          </div>
        </div>
      </div>

      <div :if={@actions != []} style="margin-top:20px;display:flex;gap:10px;flex-wrap:wrap;">
        <button
          :for={action <- @actions}
          class="j-btn j-btn-ghost j-btn-sm"
          phx-click={action[:event]}
        >
          {action[:label]}
        </button>
      </div>
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # AlertBanner (Issue #20)
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Renders an alert banner (info, warn, error).
  """
  attr :kind, :atom, default: :info, values: [:info, :warn, :error]
  attr :message, :string, required: true
  attr :title, :string, default: nil
  attr :retry_event, :string, default: nil

  def alert_banner(assigns) do
    ~H"""
    <div class={"j-alert j-alert-#{@kind}"}>
      <span class="j-alert-marker">{alert_marker(@kind)}</span>
      <div style="flex:1;">
        <strong :if={@title}>{@title} — </strong>{@message}
      </div>
      <button
        :if={@retry_event}
        class="j-btn j-btn-ghost"
        phx-click={@retry_event}
        style="margin-left:12px;font-size:0.85rem;padding:4px 10px;"
      >
        Retry
      </button>
    </div>
    """
  end

  defp alert_marker(:warn), do: "!"
  defp alert_marker(:error), do: "×"
  defp alert_marker(:info), do: "i"

  # ──────────────────────────────────────────────────────────────────────────
  # EmptyState (Issue #20)
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Renders a centred empty state with icon and message.
  """
  attr :icon, :string, default: nil
  attr :title, :string, default: "Nothing here yet"
  attr :message, :string, default: nil
  slot :inner_block

  def empty_state(assigns) do
    ~H"""
    <div class="j-empty-state">
      <p class="j-empty-heading">{@title}</p>
      <p :if={@message} class="j-empty-text">{@message}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # DynamicForm (Issue #25)
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Renders a dynamic form from a UI spec field list.

  ## Field types
  - text, number, textarea, select, toggle, date

  ## Examples

      <.dynamic_form
        id="product-form"
        title="Create Product"
        fields={[
          %{key: "name", label: "Name", type: "text", required: true},
          %{key: "price", label: "Price (£)", type: "number"},
          %{key: "status", label: "Status", type: "select",
            options: ["draft", "published", "archived"]}
        ]}
        values={%{"status" => "draft"}}
        submit_event="submit_form"
        cancel_event="cancel_form"
      />
  """
  attr :id, :string, required: true
  attr :title, :string, default: nil
  attr :fields, :list, required: true
  attr :values, :map, default: %{}
  attr :submit_event, :string, default: "submit_form"
  attr :cancel_event, :string, default: nil
  attr :submit_label, :string, default: "Save"
  attr :loading, :boolean, default: false

  def dynamic_form(assigns) do
    ~H"""
    <div class="j-card" style="padding:24px;">
      <h2 :if={@title} class="j-card-title">{@title}</h2>
      <form id={@id} phx-submit={@submit_event} style="display:flex;flex-direction:column;gap:18px;">
        <.form_field :for={field <- @fields} field={field} values={@values} />
        <div style="display:flex;gap:10px;margin-top:8px;">
          <button type="submit" class="j-btn j-btn-solid" disabled={@loading}>
            {if @loading, do: "Saving…", else: @submit_label}
          </button>
          <button
            :if={@cancel_event}
            type="button"
            class="j-btn j-btn-ghost"
            phx-click={@cancel_event}
          >
            Cancel
          </button>
        </div>
      </form>
    </div>
    """
  end

  attr :field, :map, required: true
  attr :values, :map, default: %{}

  def form_field(assigns) do
    field = assigns.field
    key = field["key"] || field[:key] || ""
    label = field["label"] || field[:label] || key
    type = field["type"] || field[:type] || "text"
    required = field["required"] || field[:required] || false
    values = assigns.values
    current = Map.get(values, key) || Map.get(values, String.to_atom(key)) || ""
    placeholder = field["placeholder"] || field[:placeholder] || ""
    options = field["options"] || field[:options] || []

    assigns =
      assigns
      |> Map.put(:fkey, key)
      |> Map.put(:flabel, label)
      |> Map.put(:ftype, type)
      |> Map.put(:frequired, required)
      |> Map.put(:fcurrent, current)
      |> Map.put(:fplaceholder, placeholder)
      |> Map.put(:foptions, options)
      |> Map.put(:finput_type, if(type == "number", do: "number", else: "text"))

    case type do
      "textarea" ->
        ~H"""
        <div>
          <label for={@fkey} class="j-form-label">
            {@flabel}<span :if={@frequired} class="required">*</span>
          </label>
          <textarea
            id={@fkey}
            name={@fkey}
            class="j-input"
            rows="4"
            placeholder={@fplaceholder}
            required={@frequired}
          >{@fcurrent}</textarea>
        </div>
        """

      "select" ->
        ~H"""
        <div>
          <label for={@fkey} class="j-form-label">
            {@flabel}<span :if={@frequired} class="required">*</span>
          </label>
          <select id={@fkey} name={@fkey} class="j-input" required={@frequired}>
            <option :for={opt <- @foptions} value={opt} selected={opt == @fcurrent}>{opt}</option>
          </select>
        </div>
        """

      "toggle" ->
        ~H"""
        <div style="display:flex;align-items:center;gap:12px;">
          <label class="j-form-label" style="margin:0;">{@flabel}</label>
          <input type="checkbox" id={@fkey} name={@fkey} checked={@fcurrent in [true, "true", "on"]} />
        </div>
        """

      "date" ->
        ~H"""
        <div>
          <label for={@fkey} class="j-form-label">
            {@flabel}<span :if={@frequired} class="required">*</span>
          </label>
          <input
            type="date"
            id={@fkey}
            name={@fkey}
            class="j-input"
            value={@fcurrent}
            required={@frequired}
          />
        </div>
        """

      _other ->
        ~H"""
        <div>
          <label for={@fkey} class="j-form-label">
            {@flabel}<span :if={@frequired} class="required">*</span>
          </label>
          <input
            type={@finput_type}
            id={@fkey}
            name={@fkey}
            class="j-input"
            value={@fcurrent}
            placeholder={@fplaceholder}
            required={@frequired}
          />
        </div>
        """
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # ActivityFeed (Issue #28)
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Renders an agent activity feed with timeline events and approval UI.

  Event kinds: :thinking, :tool_started, :tool_finished, :awaiting_approval, :text
  """
  attr :events, :list, default: []
  attr :id, :string, default: "activity-feed"

  def activity_feed(assigns) do
    ~H"""
    <div class="j-card" id={@id} style="padding:20px;">
      <h2 class="j-card-title">Agent Activity</h2>
      <div :if={@events == []} class="j-empty-state" style="padding:24px;">
        <p class="j-empty-text">No activity yet</p>
      </div>
      <div :if={@events != []}>
        <div :for={event <- @events} class="j-activity-item">
          <span class="j-activity-marker">{activity_marker(event[:kind])}</span>
          <div style="flex:1;">
            <span>{activity_label(event)}</span>
            <div :if={event[:kind] == :awaiting_approval} style="margin-top:8px;display:flex;gap:8px;">
              <button
                class="j-btn j-btn-solid j-btn-sm"
                phx-click="approve_action"
                phx-value-id={event[:id]}
              >
                Approve
              </button>
              <button
                class="j-btn j-btn-ghost j-btn-sm"
                phx-click="reject_action"
                phx-value-id={event[:id]}
              >
                Reject
              </button>
            </div>
          </div>
          <span class="j-activity-time">{event[:time]}</span>
        </div>
      </div>
    </div>
    """
  end

  defp activity_marker(:thinking), do: "·"
  defp activity_marker(:tool_started), do: "→"
  defp activity_marker(:tool_finished), do: "✓"
  defp activity_marker(:awaiting_approval), do: "!"
  defp activity_marker(_), do: "·"

  defp activity_label(%{kind: :thinking} = e),
    do: "Thinking… (#{e[:model]}, #{e[:tokens]} tokens)"

  defp activity_label(%{kind: :tool_started} = e),
    do: "Tool started: #{e[:tool]} #{if e[:args], do: "— #{e[:args]}", else: ""}"

  defp activity_label(%{kind: :tool_finished} = e),
    do: "Tool finished: #{e[:tool]} (#{e[:duration_ms]}ms)"

  defp activity_label(%{kind: :awaiting_approval} = e),
    do: "Awaiting approval: #{e[:description]}"

  defp activity_label(%{kind: :text} = e), do: e[:text]
  defp activity_label(e), do: to_string(e[:text] || e[:kind])

  # ──────────────────────────────────────────────────────────────────────────
  # Chart (Issue #29)
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Renders a Chart.js chart via a LiveView hook.

  ## Examples

      <.chart
        id="sales-chart"
        title="Daily Revenue"
        type="line"
        labels={["Mon","Tue","Wed","Thu","Fri"]}
        datasets={[%{label: "Revenue", data: [120,145,98,210,189]}]}
      />
  """
  attr :id, :string, required: true
  attr :title, :string, default: nil
  attr :type, :string, default: "line", values: ~w(line bar doughnut)
  attr :labels, :list, required: true
  attr :datasets, :list, required: true
  attr :height, :integer, default: 280

  def chart(assigns) do
    chart_data =
      Jason.encode!(%{
        type: assigns.type,
        labels: assigns.labels,
        datasets: assigns.datasets
      })

    assigns = assign(assigns, :chart_data, chart_data)

    ~H"""
    <div class="j-card" style="padding:20px;">
      <h2 :if={@title} class="j-card-title">{@title}</h2>
      <div class="j-chart-wrap" style={"height:#{@height}px;"}>
        <canvas
          id={@id}
          phx-hook="Chart"
          data-chart={@chart_data}
          style="width:100%;height:100%;"
        >
        </canvas>
      </div>
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # StatBar
  # ──────────────────────────────────────────────────────────────────────────

  attr :stats, :list, required: true

  def stat_bar(assigns) do
    ~H"""
    <div class="j-stat-bar">
      <div :for={s <- @stats} class="j-stat-bar-item">
        <div class="j-stat-bar-value">{s["value"] || s[:value]}</div>
        <div class="j-stat-bar-label">{s["label"] || s[:label]}</div>
        <div
          :if={s["delta"] || s[:delta]}
          class={"j-stat-bar-delta #{if s["delta_up"] != false && s[:delta_up] != false, do: "j-trend-up", else: "j-trend-down"}"}
        >
          {s["delta"] || s[:delta]}
        </div>
      </div>
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Breadcrumb
  # ──────────────────────────────────────────────────────────────────────────

  attr :crumbs, :list, required: true

  def breadcrumb(assigns) do
    ~H"""
    <div class="j-breadcrumb">
      <span :for={{crumb, idx} <- Enum.with_index(@crumbs)}>
        <span :if={idx > 0} class="j-breadcrumb-sep">/</span>
        <button
          :if={crumb["event"] || crumb[:event]}
          class="j-breadcrumb-link"
          phx-click={crumb["event"] || crumb[:event]}
          phx-value-id={crumb["value"] || crumb[:value]}
        >
          {crumb["label"] || crumb[:label]}
        </button>
        <span
          :if={!(crumb["event"] || crumb[:event])}
          class="j-breadcrumb-current"
        >
          {crumb["label"] || crumb[:label]}
        </span>
      </span>
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # ActionBar
  # ──────────────────────────────────────────────────────────────────────────

  attr :actions, :list, required: true
  attr :back_event, :string, default: nil
  attr :back_label, :string, default: "Back"

  def action_bar(assigns) do
    ~H"""
    <div class="j-action-bar">
      <button
        :if={@back_event}
        class="j-back-btn"
        phx-click={@back_event}
      >
        <span class="j-back-btn-arrow">←</span> {@back_label}
      </button>
      <span :if={@back_event} style="flex:1;" />
      <button
        :for={action <- @actions}
        class={"j-btn j-btn-sm #{if (action["style"] || action[:style]) == "solid", do: "j-btn-solid", else: "j-btn-ghost"}"}
        phx-click={action["event"] || action[:event]}
        phx-value-id={action["value"] || action[:value]}
        phx-value-resource={action["resource"] || action[:resource]}
      >
        {action["label"] || action[:label]}
      </button>
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # ProductGrid
  # ──────────────────────────────────────────────────────────────────────────

  attr :title, :string, default: nil
  attr :products, :list, required: true
  attr :on_click, :string, default: "view_product"

  def product_grid(assigns) do
    ~H"""
    <div>
      <div :if={@title} class="j-section-header" style="margin-bottom:16px;">
        <p class="j-section-title">{@title}</p>
      </div>
      <div class="j-product-grid">
        <div
          :for={p <- @products}
          class="j-product-card"
          phx-click={@on_click}
          phx-value-id={p["id"] || p[:id]}
        >
          <div class="j-product-card-img">
            {p["sku"] || p[:sku]}
          </div>
          <div class="j-product-card-body">
            <p class="j-product-card-name">{p["name"] || p[:name]}</p>
            <div style="display:flex;align-items:baseline;gap:4px;">
              <span class="j-product-card-price">{p["price"] || p[:price]}</span>
              <span :if={p["compare_at"] || p[:compare_at]} class="j-product-card-compare">
                {p["compare_at"] || p[:compare_at]}
              </span>
            </div>
            <p class="j-product-card-stock">
              {stock_label(p["stock"] || p[:stock])}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp stock_label(nil), do: ""
  defp stock_label(0), do: "Out of stock"
  defp stock_label(n) when is_integer(n) and n <= 5, do: "#{n} left"
  defp stock_label(n) when is_integer(n), do: "#{n} in stock"
  defp stock_label(s) when is_binary(s), do: stock_label(String.to_integer(s))

  # ──────────────────────────────────────────────────────────────────────────
  # OrderDetail
  # ──────────────────────────────────────────────────────────────────────────

  attr :order, :map, required: true
  attr :on_back, :string, default: "clear_detail"

  def order_detail(assigns) do
    {status_text, status_class} =
      JargaAdmin.Util.status_badge(assigns.order["status"] || "")

    assigns = assign(assigns, status_text: status_text, status_class: status_class)

    ~H"""
    <div>
      <button class="j-back-btn" phx-click={@on_back}>
        <span class="j-back-btn-arrow">←</span> Orders
      </button>

      <div class="j-breadcrumb">
        <button class="j-breadcrumb-link" phx-click={@on_back}>Orders</button>
        <span class="j-breadcrumb-sep">/</span>
        <span class="j-breadcrumb-current">{@order["id"]}</span>
      </div>

      <div style="display:flex;align-items:center;gap:14px;margin-bottom:24px;">
        <h1 style="font-family:'Noto Serif Display',Georgia,serif;font-size:clamp(1.4rem,3vw,2rem);font-weight:600;color:var(--text-primary);">
          Order {@order["id"]}
        </h1>
        <span class={"j-badge #{@status_class}"}>{@status_text}</span>
      </div>

      <div class="j-kpi-row">
        <div>
          <p class="j-kpi-label">Order total</p>
          <p class="j-kpi-value">{@order["total"]}</p>
        </div>
        <div>
          <p class="j-kpi-label">Items</p>
          <p class="j-kpi-value">{length(@order["items"] || [])}</p>
        </div>
        <div>
          <p class="j-kpi-label">Date placed</p>
          <p class="j-kpi-value" style="font-size:1rem;">{@order["date"]}</p>
        </div>
        <div>
          <p class="j-kpi-label">Payment</p>
          <p class="j-kpi-value" style="font-size:1rem;">
            {String.capitalize(@order["payment"] || "")}
          </p>
        </div>
      </div>

      <div class="j-detail-grid">
        <%!-- Left: line items --%>
        <div>
          <div class="j-card" style="padding:20px 24px;">
            <p class="j-card-title">Items</p>
            <table class="j-line-items">
              <tbody>
                <tr :for={item <- @order["items"] || []}>
                  <td style="padding-right:16px;">
                    <span class="j-li-name">{item["name"]}</span>
                    <span class="j-li-variant">{item["variant"]} · {item["sku"]}</span>
                  </td>
                  <td class="j-li-qty">× {item["qty"]}</td>
                  <td class="j-li-total">{item["price"]}</td>
                </tr>
              </tbody>
            </table>
            <table class="j-totals" style="margin-top:16px;">
              <tr>
                <td>Subtotal</td>
                <td>{@order["subtotal"]}</td>
              </tr>
              <tr>
                <td>Shipping</td>
                <td>{@order["shipping"]}</td>
              </tr>
              <tr>
                <td>Tax (VAT 20%)</td>
                <td>{@order["tax"]}</td>
              </tr>
              <tr class="total">
                <td>Total</td>
                <td>{@order["total"]}</td>
              </tr>
            </table>
          </div>

          <%!-- Timeline --%>
          <div class="j-card" style="padding:20px 24px;margin-top:16px;">
            <p class="j-card-title">Timeline</p>
            <div class="j-timeline">
              <div :for={event <- @order["timeline"] || []} class="j-timeline-item">
                <div class="j-timeline-dot"></div>
                <div>
                  <p class="j-timeline-title">{event["event"]}</p>
                  <p class="j-timeline-time">{event["time"]}</p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Right: customer + address --%>
        <div style="display:flex;flex-direction:column;gap:16px;">
          <div class="j-card" style="padding:20px 24px;">
            <p class="j-card-title">Customer</p>
            <div style="display:flex;align-items:center;gap:12px;margin-bottom:16px;">
              <div class="j-avatar">{JargaAdmin.Util.initials(@order["customer"] || "?")}</div>
              <div>
                <p style="font-family:'Manrope',sans-serif;font-weight:600;font-size:0.9rem;color:var(--text-primary);">
                  {@order["customer"]}
                </p>
                <p style="font-family:'Manrope',sans-serif;font-size:0.82rem;color:var(--text-faint);">
                  {@order["email"]}
                </p>
              </div>
            </div>
            <div class="j-kv-list">
              <div class="j-kv-row">
                <span class="j-kv-key">Address</span>
                <span class="j-kv-val">{@order["address"]}</span>
              </div>
              <div class="j-kv-row">
                <span class="j-kv-key">Fulfillment</span>
                <span class="j-kv-val">{String.capitalize(@order["fulfillment"] || "")}</span>
              </div>
            </div>
          </div>

          <div
            class="j-action-bar"
            style="margin-top:0;padding-top:0;border-top:none;flex-direction:column;align-items:stretch;gap:8px;"
          >
            <button
              class="j-btn j-btn-solid j-btn-sm"
              phx-click="fulfill_order"
              phx-value-id={@order["id"]}
            >
              Mark as fulfilled
            </button>
            <button
              class="j-btn j-btn-ghost j-btn-sm"
              phx-click="refund_order"
              phx-value-id={@order["id"]}
            >
              Issue refund
            </button>
            <button
              class="j-btn j-btn-ghost j-btn-sm"
              phx-click="view_customer"
              phx-value-id={@order["customer_id"]}
            >
              View customer
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # ProductDetail
  # ──────────────────────────────────────────────────────────────────────────

  attr :product, :map, required: true
  attr :on_back, :string, default: "clear_detail"

  def product_detail(assigns) do
    stock = assigns.product["stock"] || 0
    reorder_at = assigns.product["reorder_at"] || 10
    pct = JargaAdmin.Util.stock_pct(stock, reorder_at)
    bar_class = JargaAdmin.Util.stock_class(stock, reorder_at)

    {status_text, status_class} =
      JargaAdmin.Util.status_badge(assigns.product["status"] || "")

    assigns =
      assigns
      |> assign(:stock_pct, pct)
      |> assign(:bar_class, bar_class)
      |> assign(:status_text, status_text)
      |> assign(:status_class, status_class)

    ~H"""
    <div>
      <button class="j-back-btn" phx-click={@on_back}>
        <span class="j-back-btn-arrow">←</span> Products
      </button>

      <div class="j-breadcrumb">
        <button class="j-breadcrumb-link" phx-click={@on_back}>Products</button>
        <span class="j-breadcrumb-sep">/</span>
        <span class="j-breadcrumb-current">{@product["name"]}</span>
      </div>

      <div style="display:flex;align-items:center;gap:14px;margin-bottom:24px;">
        <h1 style="font-family:'Noto Serif Display',Georgia,serif;font-size:clamp(1.4rem,3vw,2rem);font-weight:600;color:var(--text-primary);">
          {@product["name"]}
        </h1>
        <span class={"j-badge #{@status_class}"}>{@status_text}</span>
      </div>

      <div :if={@product["stock"] == 0} style="margin-bottom:20px;">
        <.alert_banner
          kind={:error}
          title="Out of stock"
          message="This product has no inventory. It is hidden from the storefront."
        />
      </div>
      <div
        :if={@product["stock"] != 0 && @product["stock"] <= @product["reorder_at"]}
        style="margin-bottom:20px;"
      >
        <.alert_banner
          kind={:warn}
          title="Low stock"
          message={"Only #{@product["stock"]} units remaining — below the reorder point of #{@product["reorder_at"]}."}
        />
      </div>

      <div class="j-kpi-row">
        <div>
          <p class="j-kpi-label">Price</p>
          <p class="j-kpi-value">{@product["price"]}</p>
        </div>
        <div>
          <p class="j-kpi-label">Stock</p>
          <p class="j-kpi-value">{@product["stock"]}</p>
        </div>
        <div>
          <p class="j-kpi-label">Revenue (30d)</p>
          <p class="j-kpi-value">{@product["revenue_30d"]}</p>
        </div>
        <div>
          <p class="j-kpi-label">Units sold (30d)</p>
          <p class="j-kpi-value">{@product["units_sold_30d"]}</p>
        </div>
      </div>

      <div class="j-detail-grid">
        <%!-- Left: product info --%>
        <div style="display:flex;flex-direction:column;gap:16px;">
          <div class="j-card" style="padding:20px 24px;">
            <p class="j-card-title">Details</p>
            <div class="j-kv-list">
              <div class="j-kv-row">
                <span class="j-kv-key">SKU</span>
                <span
                  class="j-kv-val"
                  style="font-family:'Montserrat',sans-serif;font-size:0.85rem;letter-spacing:0.05em;"
                >
                  {@product["sku"]}
                </span>
              </div>
              <div class="j-kv-row">
                <span class="j-kv-key">Weight</span>
                <span class="j-kv-val">{@product["weight"]}</span>
              </div>
              <div :if={@product["compare_at"]} class="j-kv-row">
                <span class="j-kv-key">Compare at</span>
                <span class="j-kv-val" style="text-decoration:line-through;">
                  {@product["compare_at"]}
                </span>
              </div>
              <div class="j-kv-row">
                <span class="j-kv-key">Tags</span>
                <span class="j-kv-val">{Enum.join(@product["tags"] || [], ", ")}</span>
              </div>
            </div>
          </div>

          <div class="j-card" style="padding:20px 24px;">
            <p class="j-card-title">Description</p>
            <p style="font-family:'Manrope',sans-serif;font-size:0.9rem;color:var(--text-body);line-height:1.7;">
              {@product["description"]}
            </p>
          </div>
        </div>

        <%!-- Right: inventory + variants --%>
        <div style="display:flex;flex-direction:column;gap:16px;">
          <div class="j-card" style="padding:20px 24px;">
            <p class="j-card-title">Inventory</p>
            <div style="margin-bottom:16px;">
              <div style="display:flex;justify-content:space-between;margin-bottom:6px;">
                <span class="j-eyebrow">Stock level</span>
                <span style="font-family:'Manrope',sans-serif;font-size:0.82rem;color:var(--text-muted);">
                  {@product["stock"]} / reorder at {@product["reorder_at"]}
                </span>
              </div>
              <div class="j-inv-bar-wrap">
                <div class={"j-inv-bar-fill #{@bar_class}"} style={"width:#{@stock_pct}%;"} />
              </div>
            </div>
            <table class="j-table" style="width:100%;">
              <thead>
                <tr>
                  <th>Variant</th>
                  <th>SKU</th>
                  <th style="text-align:right;">Stock</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={v <- @product["variants"] || []}>
                  <td>{v["name"]}</td>
                  <td style="font-family:'Montserrat',sans-serif;font-size:0.78rem;letter-spacing:0.05em;color:var(--text-faint);">
                    {v["sku"]}
                  </td>
                  <td style="text-align:right;">
                    <span class={if v["stock"] == 0, do: "j-badge j-badge-red", else: ""}>
                      {v["stock"]}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div style="display:flex;flex-direction:column;gap:8px;">
            <button
              class="j-btn j-btn-solid j-btn-sm"
              phx-click="edit_product"
              phx-value-id={@product["id"]}
            >
              Edit product
            </button>
            <button
              class="j-btn j-btn-ghost j-btn-sm"
              phx-click="duplicate_product"
              phx-value-id={@product["id"]}
            >
              Duplicate
            </button>
            <button
              class="j-btn j-btn-ghost j-btn-sm"
              phx-click="archive_product"
              phx-value-id={@product["id"]}
            >
              Archive
            </button>
            <button
              class="j-btn j-btn-ghost j-btn-sm"
              style="color:#c0392b;border-color:#c0392b;"
              phx-click="delete_product"
              phx-value-id={@product["id"]}
              data-confirm="Are you sure? This will permanently delete the product."
            >
              Delete
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # CustomerDetail
  # ──────────────────────────────────────────────────────────────────────────

  attr :customer, :map, required: true
  attr :on_back, :string, default: "clear_detail"
  attr :recent_orders, :list, default: []

  def customer_detail(assigns) do
    {seg_text, seg_class} = segment_badge(assigns.customer["segment"])
    assigns = assign(assigns, seg_text: seg_text, seg_class: seg_class)

    ~H"""
    <div>
      <button class="j-back-btn" phx-click={@on_back}>
        <span class="j-back-btn-arrow">←</span> Customers
      </button>

      <div class="j-breadcrumb">
        <button class="j-breadcrumb-link" phx-click={@on_back}>Customers</button>
        <span class="j-breadcrumb-sep">/</span>
        <span class="j-breadcrumb-current">{@customer["name"]}</span>
      </div>

      <div style="display:flex;align-items:center;gap:16px;margin-bottom:24px;">
        <div class="j-avatar j-avatar-lg">
          {JargaAdmin.Util.initials(@customer["name"] || "?")}
        </div>
        <div>
          <div style="display:flex;align-items:center;gap:10px;">
            <h1 style="font-family:'Noto Serif Display',Georgia,serif;font-size:clamp(1.3rem,2.5vw,1.8rem);font-weight:600;color:var(--text-primary);">
              {@customer["name"]}
            </h1>
            <span class={"j-badge #{@seg_class}"}>{@seg_text}</span>
          </div>
          <p style="font-family:'Manrope',sans-serif;font-size:0.88rem;color:var(--text-faint);margin-top:2px;">
            {@customer["email"]} · {@customer["location"]}
          </p>
        </div>
      </div>

      <div class="j-kpi-row">
        <div>
          <p class="j-kpi-label">Lifetime value</p>
          <p class="j-kpi-value">{@customer["ltv"]}</p>
        </div>
        <div>
          <p class="j-kpi-label">Orders</p>
          <p class="j-kpi-value">{@customer["order_count"]}</p>
        </div>
        <div>
          <p class="j-kpi-label">Avg order value</p>
          <p class="j-kpi-value">{@customer["avg_order"]}</p>
        </div>
        <div>
          <p class="j-kpi-label">Return rate</p>
          <p class="j-kpi-value">{@customer["return_rate"]}</p>
        </div>
      </div>

      <div class="j-detail-grid">
        <div>
          <div class="j-card" style="padding:20px 24px;">
            <p class="j-card-title">Recent orders</p>
            <div :if={@recent_orders == []} class="j-empty-state" style="padding:24px;">
              <p class="j-empty-text">No orders yet</p>
            </div>
            <table class="j-table" style="width:100%;">
              <thead>
                <tr>
                  <th>Order</th>
                  <th>Date</th>
                  <th>Total</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={ord <- @recent_orders}
                  style="cursor:pointer;"
                  phx-click="view_order"
                  phx-value-id={ord["id"]}
                >
                  <td style="font-family:'Montserrat',sans-serif;font-size:0.82rem;font-weight:700;letter-spacing:0.05em;">
                    {ord["id"]}
                  </td>
                  <td>{ord["date"]}</td>
                  <td style="font-family:'Noto Serif Display',serif;font-weight:600;">
                    {ord["total"]}
                  </td>
                  <td>{elem(JargaAdmin.Util.status_badge(ord["status"]), 0)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div style="display:flex;flex-direction:column;gap:16px;">
          <div class="j-card" style="padding:20px 24px;">
            <p class="j-card-title">Details</p>
            <div class="j-kv-list">
              <div class="j-kv-row">
                <span class="j-kv-key">Customer since</span>
                <span class="j-kv-val">{@customer["joined"]}</span>
              </div>
              <div class="j-kv-row">
                <span class="j-kv-key">Segment</span>
                <span class="j-kv-val">{@customer["segment"]}</span>
              </div>
              <div class="j-kv-row">
                <span class="j-kv-key">Location</span>
                <span class="j-kv-val">{@customer["location"]}</span>
              </div>
            </div>
          </div>
          <div style="display:flex;flex-direction:column;gap:8px;">
            <button
              class="j-btn j-btn-solid j-btn-sm"
              phx-click="edit_customer"
              phx-value-id={@customer["id"]}
            >
              Edit customer
            </button>
            <button class="j-btn j-btn-ghost j-btn-sm">Email customer</button>
            <button
              class="j-btn j-btn-ghost j-btn-sm"
              style="color:#c0392b;border-color:#c0392b;"
              phx-click="delete_customer"
              phx-value-id={@customer["id"]}
              data-confirm="Are you sure? This will permanently delete the customer."
            >
              Delete customer
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp segment_badge("VIP"), do: {"VIP", "j-badge-green"}
  defp segment_badge("Loyal"), do: {"Loyal", "j-badge-green"}
  defp segment_badge("Regular"), do: {"Regular", "j-badge-amber"}
  defp segment_badge("New"), do: {"New", "j-badge-muted"}
  defp segment_badge(s), do: {s || "", "j-badge-muted"}

  # ──────────────────────────────────────────────────────────────────────────
  # PromotionList
  # ──────────────────────────────────────────────────────────────────────────

  attr :promotions, :list, required: true
  attr :title, :string, default: "Promotions"
  attr :on_click, :string, default: "view_promotion"

  def promotion_list(assigns) do
    ~H"""
    <div>
      <div class="j-section-header">
        <p class="j-section-title">{@title}</p>
      </div>
      <div class="j-promo-list">
        <div
          :for={promo <- @promotions}
          class="j-promo-card"
          phx-click={@on_click}
          phx-value-id={promo["id"] || promo[:id]}
          style="cursor:pointer;"
        >
          <div class="j-promo-left">
            <div style="display:flex;align-items:center;gap:10px;margin-bottom:4px;">
              <p class="j-promo-code">{promo["code"] || promo[:code]}</p>
              <span class={promo_badge_class(promo["status"] || promo[:status])}>
                {String.capitalize(promo["status"] || promo[:status] || "")}
              </span>
            </div>
            <p class="j-promo-desc">{promo["description"] || promo[:description]}</p>
            <p class="j-promo-meta">
              {promo["value"] || promo[:value]} off {if promo["expires"] || promo[:expires],
                do: "· Expires #{promo["expires"] || promo[:expires]}",
                else: "· No expiry"} · {promo["conditions"] || promo[:conditions]}
            </p>
          </div>
          <div class="j-promo-right">
            <div class="j-promo-uses-value">{promo["uses"] || promo[:uses] || 0}</div>
            <div class="j-promo-uses-label">uses</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp promo_badge_class("active"), do: "j-badge j-badge-green"
  defp promo_badge_class("expired"), do: "j-badge j-badge-muted"
  defp promo_badge_class(_), do: "j-badge j-badge-muted"

  # ──────────────────────────────────────────────────────────────────────────
  # InventoryTable
  # ──────────────────────────────────────────────────────────────────────────

  attr :title, :string, default: "Inventory"
  attr :rows, :list, required: true
  attr :on_restock, :string, default: nil

  def inventory_table(assigns) do
    ~H"""
    <div class="j-card" style="padding:20px 24px;">
      <p class="j-card-title">{@title}</p>
      <div class="j-table-wrap">
        <table class="j-table" style="width:100%;">
          <thead>
            <tr>
              <th>Product</th>
              <th>SKU</th>
              <th>Stock</th>
              <th>Reorder at</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows}>
              <td style="font-weight:500;color:var(--text-primary);">{row["name"] || row[:name]}</td>
              <td style="font-family:'Montserrat',sans-serif;font-size:0.78rem;letter-spacing:0.05em;color:var(--text-faint);">
                {row["sku"] || row[:sku]}
              </td>
              <td>
                <div style="display:flex;align-items:center;gap:10px;">
                  <div class="j-inv-bar-wrap">
                    <div
                      class={"j-inv-bar-fill #{JargaAdmin.Util.stock_class(row["stock"] || 0, row["reorder_at"] || 10)}"}
                      style={"width:#{JargaAdmin.Util.stock_pct(row["stock"] || 0, row["reorder_at"] || 10)}%;"}
                    />
                  </div>
                  <span style="font-family:'Manrope',sans-serif;font-size:0.85rem;">
                    {row["stock"] || row[:stock]}
                  </span>
                </div>
              </td>
              <td style="color:var(--text-faint);">{row["reorder_at"] || row[:reorder_at]}</td>
              <td>
                <button
                  :if={@on_restock}
                  class="j-btn j-btn-ghost j-btn-sm"
                  phx-click={@on_restock}
                  phx-value-id={row["id"] || row[:id]}
                >
                  Restock
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Inventory Detail Table (full SKU-level inventory view)
  # ──────────────────────────────────────────────────────────────────────────

  attr :title, :string, default: "Inventory"
  attr :rows, :list, required: true

  def inventory_detail_table(assigns) do
    ~H"""
    <div class="j-card">
      <div style="padding:20px 20px 0;">
        <h2 :if={@title} class="j-card-title">{@title}</h2>
      </div>
      <div class="j-table-wrap">
        <table class="j-table">
          <thead>
            <tr>
              <th>Product</th>
              <th>Variant</th>
              <th>SKU</th>
              <th>Available</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows}>
              <td style="font-weight:500;color:var(--text-primary);">
                {row["product"] || "—"}
              </td>
              <td style="color:var(--text-secondary);">{row["variant"] || "—"}</td>
              <td style="font-family:'Montserrat',sans-serif;font-size:0.78rem;letter-spacing:0.05em;color:var(--text-faint);">
                {row["sku"] || "—"}
              </td>
              <td style="font-family:'Manrope',sans-serif;">{row["available"] || 0}</td>
              <td>
                <span class={"j-badge #{inventory_status_class(row["status"])}"}>
                  {inventory_status_label(row["status"])}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp inventory_status_class("out_of_stock"), do: "j-badge-red"
  defp inventory_status_class("low_stock"), do: "j-badge-amber"
  defp inventory_status_class(_), do: "j-badge-green"

  defp inventory_status_label("out_of_stock"), do: "Out of stock"
  defp inventory_status_label("low_stock"), do: "Low stock"
  defp inventory_status_label(_), do: "In stock"

  # ──────────────────────────────────────────────────────────────────────────
  # Analytics Revenue — monthly bar chart (text-based)
  # ──────────────────────────────────────────────────────────────────────────

  attr :title, :string, default: "Revenue by month"
  attr :rows, :list, required: true

  def analytics_revenue(assigns) do
    assigns =
      assign(
        assigns,
        :max_revenue,
        Enum.max_by(assigns.rows, & &1["revenue"], fn -> %{"revenue" => 1} end)["revenue"]
      )

    ~H"""
    <div class="j-card" style="padding:24px;">
      <h2 class="j-card-title">{@title}</h2>
      <div class="j-analytics-bars">
        <div :for={row <- @rows} class="j-analytics-bar-col">
          <div class="j-analytics-bar-label-top">
            {format_pence_short(row["revenue"] || 0)}
          </div>
          <div class="j-analytics-bar-wrap">
            <div
              class="j-analytics-bar-fill"
              style={"height:#{bar_pct(row["revenue"] || 0, @max_revenue)}%;"}
            />
          </div>
          <div class="j-analytics-bar-label">{row["month"] || "—"}</div>
          <div class="j-analytics-bar-count">{row["count"] || 0} orders</div>
        </div>
      </div>
    </div>
    """
  end

  defp bar_pct(_val, 0), do: 5
  defp bar_pct(val, max) when max > 0, do: max(5, round(val / max * 100))

  defp format_pence_short(pence) when is_integer(pence) and pence >= 100_00 do
    "£#{div(pence, 100_00) |> Integer.to_string()}k"
  end

  defp format_pence_short(pence) when is_integer(pence) do
    pounds = div(pence, 100)
    cents = rem(pence, 100)
    "£#{pounds}.#{String.pad_leading("#{cents}", 2, "0")}"
  end

  defp format_pence_short(_), do: "—"

  # ──────────────────────────────────────────────────────────────────────────
  # Analytics Breakdown — orders by status table
  # ──────────────────────────────────────────────────────────────────────────

  attr :title, :string, default: "Orders by status"
  attr :rows, :list, required: true

  def analytics_breakdown(assigns) do
    assigns =
      assign(assigns, :total, Enum.sum(Enum.map(assigns.rows, & &1["count"])))

    ~H"""
    <div class="j-card" style="padding:24px;">
      <h2 class="j-card-title">{@title}</h2>
      <div class="j-table-wrap">
        <table class="j-table">
          <thead>
            <tr>
              <th>Status</th>
              <th>Orders</th>
              <th>Share</th>
              <th>Revenue</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows}>
              <td style="font-weight:500;color:var(--text-primary);">{row["status"] || "—"}</td>
              <td style="font-family:'Manrope',sans-serif;">{row["count"] || 0}</td>
              <td style="color:var(--text-secondary);">
                {if @total > 0, do: "#{round((row["count"] || 0) / @total * 100)}%", else: "—"}
              </td>
              <td style="font-family:'Manrope',sans-serif;">
                {format_pence_comp(row["revenue"] || 0)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp format_pence_comp(pence) when is_integer(pence) do
    pounds = div(pence, 100)
    cents = rem(pence, 100)
    "£#{pounds}.#{String.pad_leading("#{cents}", 2, "0")}"
  end

  defp format_pence_comp(_), do: "—"

  # ──────────────────────────────────────────────────────────────────────────
  # Shipping Zones Table
  # ──────────────────────────────────────────────────────────────────────────

  attr :title, :string, default: "Shipping zones"
  attr :zones, :list, required: true
  attr :on_click, :string, default: "view_shipping_zone"

  def shipping_zones_table(assigns) do
    ~H"""
    <div class="j-card">
      <div style="padding:20px 20px 0;">
        <h2 class="j-card-title">{@title}</h2>
      </div>
      <div class="j-table-wrap">
        <table class="j-table">
          <thead>
            <tr>
              <th>Zone</th>
              <th>Countries</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={zone <- @zones}
              phx-click={@on_click}
              phx-value-id={zone["id"]}
              class="j-table-row-clickable"
              style="cursor:pointer;"
            >
              <td style="font-weight:500;color:var(--text-primary);">{zone["name"] || "—"}</td>
              <td style="color:var(--text-secondary);font-size:0.85rem;">
                {zone["countries"] || "—"}
                <span :if={(zone["total_countries"] || 0) > 5} style="color:var(--text-faint);">
                  + {(zone["total_countries"] || 5) - 5} more
                </span>
              </td>
              <td>
                <span class={"j-badge #{if zone["active"] == "Active", do: "j-badge-green", else: "j-badge-grey"}"}>
                  {zone["active"] || "—"}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Search Bar
  # ──────────────────────────────────────────────────────────────────────────

  @doc "Renders a search input bar that submits a 'search' event."
  attr :tab_id, :string, required: true
  attr :placeholder, :string, default: "Search…"
  attr :value, :string, default: ""
  attr :filters, :list, default: []

  def search_bar(assigns) do
    ~H"""
    <form
      class="j-search-bar flex gap-2 items-center px-1 py-2"
      phx-submit="search"
    >
      <input type="hidden" name="tab_id" value={@tab_id} />
      <input
        class="j-search-input flex-1 rounded-lg border border-gray-200 bg-white px-3 py-1.5 text-sm placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-violet-500"
        type="text"
        name="q"
        value={@value}
        placeholder={@placeholder}
        autocomplete="off"
      />
      <button class="j-btn j-btn-ghost j-btn-sm" type="submit">Search</button>
      <button
        :if={@value != ""}
        class="j-btn j-btn-ghost j-btn-sm"
        type="button"
        phx-click="clear_filter"
        phx-value-tab_id={@tab_id}
      >
        Clear
      </button>
    </form>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Confirmation Dialog
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Renders a modal confirmation dialog for destructive actions.
  Pass `show={true}` with `title`, `message`, and optional `variant` (:destructive | :normal).
  Emits `confirm_action` and `cancel_confirm` events.
  """
  attr :show, :boolean, default: false
  attr :title, :string, default: "Are you sure?"
  attr :message, :string, default: "This action cannot be undone."
  attr :variant, :atom, default: :destructive
  attr :confirm_label, :string, default: "Confirm"
  attr :cancel_label, :string, default: "Cancel"

  def confirmation_dialog(assigns) do
    ~H"""
    <div :if={@show} id="confirmation-dialog" class="j-dialog-overlay" role="dialog" aria-modal="true">
      <div class="j-dialog-panel">
        <div class="j-dialog-header">
          <h3 class="j-dialog-title">{@title}</h3>
        </div>
        <div class="j-dialog-body">
          <p class="j-dialog-message">{@message}</p>
        </div>
        <div class="j-dialog-footer">
          <button
            class="j-btn j-btn-ghost"
            phx-click="cancel_confirm"
            id="confirm-dialog-cancel"
          >
            {@cancel_label}
          </button>
          <button
            class={[
              "j-btn",
              if(@variant == :destructive, do: "j-btn-danger", else: "j-btn-solid")
            ]}
            phx-click="confirm_action"
            id="confirm-dialog-confirm"
          >
            {@confirm_label}
          </button>
        </div>
      </div>
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Pagination Controls
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Renders Previous/Next pagination controls.
  Pass `page` (current page, 1-indexed), `total_pages` (optional), and
  `per_page` for display.
  """
  attr :page, :integer, default: 1
  attr :total_pages, :integer, default: nil
  attr :per_page, :integer, default: 50
  attr :total_items, :integer, default: nil

  def pagination(assigns) do
    ~H"""
    <div
      :if={@page > 1 or (@total_pages != nil and @total_pages > 1)}
      class="j-pagination flex items-center justify-between gap-3 px-2 py-3 border-t border-gray-100"
    >
      <button
        class="j-btn j-btn-ghost j-btn-sm"
        phx-click="prev_page"
        disabled={@page <= 1}
      >
        ← Previous
      </button>

      <span class="text-sm text-gray-500">
        Page {@page}
        {if @total_pages, do: "of #{@total_pages}", else: ""}
        {if @total_items, do: " (#{@total_items} total)", else: ""}
      </span>

      <button
        class="j-btn j-btn-ghost j-btn-sm"
        phx-click="next_page"
        disabled={@total_pages != nil and @page >= @total_pages}
      >
        Next →
      </button>
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Loading Spinner
  # ──────────────────────────────────────────────────────────────────────────

  @doc "Renders an inline loading spinner. Pass `loading={false}` to hide."
  attr :loading, :boolean, default: true
  attr :label, :string, default: "Loading…"
  attr :class, :string, default: ""

  def loading_spinner(assigns) do
    ~H"""
    <div
      :if={@loading}
      class={["j-loading-indicator flex items-center justify-center gap-3 py-12", @class]}
      aria-label={@label}
      aria-live="polite"
    >
      <svg
        class="j-spinner-spin animate-spin h-6 w-6 text-gray-400"
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
      >
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
        <path
          class="opacity-75"
          fill="currentColor"
          d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
        />
      </svg>
      <span class="text-sm text-gray-500">{@label}</span>
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Toast Notification Container
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Renders a stacked toast notification container.
  `toasts` is a list of maps with `:id`, `:kind`, `:message` keys.
  """
  attr :toasts, :list, default: []

  def toast_container(assigns) do
    ~H"""
    <div
      id="toast-container"
      aria-live="polite"
      aria-atomic="false"
      class="fixed bottom-6 right-6 z-50 flex flex-col gap-3 pointer-events-none"
    >
      <div
        :for={toast <- @toasts}
        id={"toast-#{toast.id}"}
        class={[
          "flex items-center gap-3 rounded-xl px-5 py-3 shadow-xl pointer-events-auto",
          "min-w-[260px] max-w-sm text-white text-sm font-medium",
          "transition-all duration-300",
          toast_bg(toast.kind)
        ]}
        role="alert"
      >
        <span class="text-lg leading-none">{toast_icon(toast.kind)}</span>
        <span class="flex-1">{toast.message}</span>
        <button
          class="ml-2 opacity-70 hover:opacity-100 transition-opacity"
          phx-click="dismiss_toast"
          phx-value-id={toast.id}
          aria-label="Dismiss"
        >
          ×
        </button>
      </div>
    </div>
    """
  end

  defp toast_bg(:success), do: "bg-emerald-600"
  defp toast_bg(:error), do: "bg-red-600"
  defp toast_bg(:warning), do: "bg-amber-500"
  defp toast_bg(:info), do: "bg-blue-600"
  defp toast_bg(_), do: "bg-gray-700"

  defp toast_icon(:success), do: "✓"
  defp toast_icon(:error), do: "✕"
  defp toast_icon(:warning), do: "⚠"
  defp toast_icon(:info), do: "ℹ"
  defp toast_icon(_), do: "●"
end
