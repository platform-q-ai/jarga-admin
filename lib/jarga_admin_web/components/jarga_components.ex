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
  attr :actions, :list, default: []
  attr :empty_message, :string, default: "No data to display"

  def data_table(assigns) do
    ~H"""
    <div class="j-card" id={@id}>
      <div style="padding:20px 20px 0;">
        <h2 :if={@title} class="j-card-title">{@title}</h2>
      </div>
      <div :if={@rows == []} class="j-empty-state">
        <div class="j-empty-icon">📭</div>
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
            <tr :for={row <- @rows}>
              <td :for={col <- @columns}>
                {render_cell(row, col)}
              </td>
              <td :if={@actions != []}>
                <div style="display:flex;gap:8px;flex-wrap:wrap;">
                  <button
                    :for={action <- @actions}
                    class="j-btn j-btn-ghost j-btn-sm"
                    phx-click={action[:event]}
                    phx-value-id={row_id(row)}
                  >
                    {action[:label]}
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

  def alert_banner(assigns) do
    ~H"""
    <div class={"j-alert j-alert-#{@kind}"}>
      <span>{alert_icon(@kind)}</span>
      <div>
        <strong :if={@title}>{@title} — </strong>{@message}
      </div>
    </div>
    """
  end

  defp alert_icon(:warn), do: "⚠️"
  defp alert_icon(:error), do: "🚨"
  defp alert_icon(:info), do: "ℹ️"

  # ──────────────────────────────────────────────────────────────────────────
  # EmptyState (Issue #20)
  # ──────────────────────────────────────────────────────────────────────────

  @doc """
  Renders a centred empty state with icon and message.
  """
  attr :icon, :string, default: "📭"
  attr :title, :string, default: "Nothing here yet"
  attr :message, :string, default: nil
  slot :inner_block

  def empty_state(assigns) do
    ~H"""
    <div class="j-empty-state">
      <div class="j-empty-icon">{@icon}</div>
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
        <div class="j-empty-icon">🤖</div>
        <p class="j-empty-text">No activity yet</p>
      </div>
      <div :if={@events != []}>
        <div :for={event <- @events} class="j-activity-item">
          <span class="j-activity-icon">{activity_icon(event[:kind])}</span>
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

  defp activity_icon(:thinking), do: "🧠"
  defp activity_icon(:tool_started), do: "🔧"
  defp activity_icon(:tool_finished), do: "✅"
  defp activity_icon(:awaiting_approval), do: "⚠️"
  defp activity_icon(_), do: "💬"

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
end
