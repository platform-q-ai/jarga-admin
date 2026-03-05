defmodule JargaAdminWeb.ChatLive do
  @moduledoc """
  Main chat + generative UI LiveView (Issue #19, #20, #23, #24).

  Layout:
  - Fixed nav + tab bar at top
  - Split: 40% chat pane (left), 60% rendered UI components (right)
  - Responsive: stacked on mobile

  Features:
  - Real-time streaming from Quecto (or MockBridge in dev)
  - UI spec parsing + rendering in right pane
  - Pinned tabs with ETS persistence
  - Auto-refresh per tab
  - Context menus on tabs (rename, duplicate, unpin)
  """

  use JargaAdminWeb, :live_view

  alias JargaAdmin.{UiSpec, Renderer, TabStore}
  alias JargaAdmin.Quecto.MockBridge
  alias Phoenix.PubSub

  @session_id "main"
  @pubsub JargaAdmin.PubSub

  # ──────────────────────────────────────────────────────────────────────────
  # Mount
  # ──────────────────────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(@pubsub, "quecto:#{@session_id}:response")
      PubSub.subscribe(@pubsub, "quecto:#{@session_id}:activity")
      PubSub.subscribe(@pubsub, "quecto:#{@session_id}:ui_spec")
      schedule_auto_refresh()
    end

    tabs = TabStore.list()
    active_tab = find_tab(tabs, "chat") || hd(tabs)

    socket =
      socket
      |> assign(:page_title, "Jarga Admin")
      |> assign(:messages, [])
      |> assign(:input, "")
      |> assign(:typing, false)
      |> assign(:streaming_text, "")
      |> assign(:tabs, tabs)
      |> assign(:active_tab_id, active_tab.id)
      |> assign(:rendered_components, active_tab.ui_spec |> Renderer.render_spec())
      |> assign(:activity_events, [])
      |> assign(:context_menu, nil)
      |> assign(:pin_modal, false)
      |> assign(:rename_tab_id, nil)
      |> assign(:rename_value, "")
      |> assign(:chat_open, true)

    {:ok, socket}
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Render
  # ──────────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Fixed nav — matches cinematic-nav from platform.html --%>
    <nav class="j-nav">
      <div class="j-nav-left">
        <span class="j-nav-badge">Admin</span>
      </div>
      <a href="/" class="j-wordmark">
        <img src={~p"/images/jarga-logo.svg"} class="j-wordmark-logo" alt="" aria-hidden="true" />
        JARGA
      </a>
      <div class="j-nav-right"></div>
    </nav>

    <%!-- Tab bar — matches .module-index from cinematic-pages.css --%>
    <div class="j-tab-bar" id="tab-bar" phx-hook="SortableTabs">
      <button
        :for={tab <- @tabs}
        class={"j-tab #{if tab.id == @active_tab_id, do: "active", else: ""}"}
        phx-click="switch_tab"
        phx-value-id={tab.id}
        data-tab-id={tab.id}
        title={tab.label}
      >
        <span>{tab.label}</span>
        <button
          :if={tab.pinnable && tab.id == @active_tab_id}
          class="j-tab-close"
          phx-click="show_context_menu"
          phx-value-id={tab.id}
          title="Tab options"
        >
          ···
        </button>
      </button>

      <%!-- Pin button — only on chat tab when a view has been generated --%>
      <button
        :if={@active_tab_id == "chat" && @rendered_components != []}
        class="j-tab"
        phx-click="show_pin_modal"
        style="border-left:1px solid var(--border-divider);padding-left:20px;"
        title="Pin this view"
      >
        Pin view
      </button>
    </div>

    <%!-- Context menu --%>
    <div
      :if={@context_menu}
      class="j-context-menu"
      id="tab-context-menu"
      style={"top:#{@context_menu.y}px;left:#{@context_menu.x}px;"}
      phx-click-away="close_context_menu"
    >
      <button class="j-context-item" phx-click="start_rename" phx-value-id={@context_menu.tab_id}>
        Rename
      </button>
      <button class="j-context-item" phx-click="duplicate_tab" phx-value-id={@context_menu.tab_id}>
        Duplicate
      </button>
      <button
        :if={
          find_tab(@tabs, @context_menu.tab_id) &&
            (find_tab(@tabs, @context_menu.tab_id) || %{}).pinnable
        }
        class="j-context-item danger"
        phx-click="unpin_tab"
        phx-value-id={@context_menu.tab_id}
      >
        Unpin
      </button>
    </div>

    <%!-- Rename modal --%>
    <div :if={@rename_tab_id} class="j-dialog-overlay" phx-click-away="cancel_rename">
      <div class="j-dialog">
        <p class="j-dialog-title">Rename Tab</p>
        <form phx-submit="confirm_rename" style="display:flex;flex-direction:column;gap:16px;">
          <input type="hidden" name="tab_id" value={@rename_tab_id} />
          <div>
            <label class="j-form-label">Name</label>
            <input name="label" class="j-input" value={@rename_value} autofocus />
          </div>
          <div style="display:flex;gap:10px;">
            <button type="submit" class="j-btn j-btn-solid">Save</button>
            <button type="button" class="j-btn j-btn-ghost" phx-click="cancel_rename">Cancel</button>
          </div>
        </form>
      </div>
    </div>

    <%!-- Pin modal --%>
    <div :if={@pin_modal} class="j-dialog-overlay" phx-click-away="cancel_pin">
      <div class="j-dialog">
        <p class="j-dialog-title">Pin This View</p>
        <form phx-submit="confirm_pin" style="display:flex;flex-direction:column;gap:14px;">
          <div>
            <label class="j-form-label">Tab name</label>
            <input name="label" class="j-input" placeholder="e.g. Low Stock Items" autofocus />
          </div>
          <div>
            <label class="j-form-label">Icon</label>
            <input name="icon" class="j-input" value="" maxlength="4" />
          </div>
          <div style="display:flex;gap:10px;margin-top:4px;">
            <button type="submit" class="j-btn j-btn-solid">Pin</button>
            <button type="button" class="j-btn j-btn-ghost" phx-click="cancel_pin">Cancel</button>
          </div>
        </form>
      </div>
    </div>

    <%!-- Main content --%>
    <div class="j-content">
      <%!-- Main canvas — full width on chat tab --%>
      <div :if={@active_tab_id == "chat"} class="j-canvas" id="chat-canvas">
        <div :if={@rendered_components == [] && !@typing} class="j-empty-state j-canvas-empty">
          <p class="j-empty-heading">Your workspace</p>
          <p class="j-empty-text">
            Ask the Jarga AI anything — generated tables, charts and forms appear here.
          </p>
        </div>
        <div :if={@rendered_components != []}>
          <div :for={comp <- @rendered_components} style="margin-bottom:24px;">
            {render_component(comp, assigns)}
          </div>
        </div>
      </div>

      <%!-- Chat popover — bottom-left, always rendered on chat tab --%>
      <div
        :if={@active_tab_id == "chat"}
        id="chat-popover"
        class={"j-chat-popover #{if @chat_open, do: "open", else: ""}"}
      >
        <%!-- Header / toggle bar --%>
        <button class="j-chat-popover-header" phx-click="toggle_chat" aria-label="Toggle chat">
          <span style="display:flex;align-items:center;gap:10px;">
            <span class="j-eyebrow" style="color:var(--ink);opacity:1;">Jarga AI</span>
            <span :if={@typing} class="j-chat-status-dot"></span>
          </span>
          <span class="j-chat-popover-chevron">{if @chat_open, do: "−", else: "+"}</span>
        </button>

        <%!-- Body — only rendered when open --%>
        <div :if={@chat_open} class="j-chat-popover-body">
          <%!-- Messages --%>
          <div class="j-chat-area" id="chat-messages" phx-hook="AutoScroll">
            <%!-- Welcome / empty --%>
            <div :if={@messages == []}>
              <div class="j-empty-state" style="padding:28px 16px;">
                <p class="j-empty-heading" style="font-size:0.95rem;">What would you like to do?</p>
                <p class="j-empty-text" style="font-size:0.8rem;">
                  Ask about orders, products, customers, analytics…
                </p>
                <div style="display:flex;flex-direction:column;gap:6px;margin-top:12px;width:100%;">
                  <button
                    :for={suggestion <- suggestions()}
                    class="j-btn j-btn-ghost j-btn-sm"
                    style="text-align:left;justify-content:flex-start;font-size:0.78rem;"
                    phx-click="use_suggestion"
                    phx-value-text={suggestion}
                  >
                    {suggestion}
                  </button>
                </div>
              </div>
            </div>

            <%!-- History --%>
            <div :for={msg <- @messages} class={"j-bubble-wrap #{msg.role}"}>
              <span class="j-bubble-label">{if msg.role == "user", do: "You", else: "Jarga"}</span>
              <div class={"j-bubble #{msg.role}"}>
                <span :if={msg.role == "user"}>{msg.content}</span>
                <span :if={msg.role == "agent"}>
                  {Phoenix.HTML.raw(md_to_html(msg.content))}
                </span>
              </div>
            </div>

            <%!-- Streaming --%>
            <div :if={@streaming_text != "" || @typing} class="j-bubble-wrap agent">
              <span class="j-bubble-label">Jarga</span>
              <div class="j-bubble agent">
                <span :if={@streaming_text != ""}>
                  {Phoenix.HTML.raw(md_to_html(@streaming_text))}
                </span>
                <div :if={@streaming_text == "" && @typing} class="j-typing">
                  <span></span><span></span><span></span>
                </div>
              </div>
            </div>
          </div>

          <%!-- Input --%>
          <div class="j-chat-input-wrap">
            <form phx-submit="send_message" phx-change="update_input" id="chat-form">
              <div style="display:flex;gap:8px;align-items:flex-end;">
                <textarea
                  name="message"
                  class="j-chat-input"
                  placeholder="Ask anything…"
                  rows="2"
                  value={@input}
                  id="chat-input"
                  phx-hook="TextareaEnter"
                  disabled={@typing}
                >{@input}</textarea>
                <button
                  type="submit"
                  class="j-btn j-btn-solid j-btn-sm"
                  disabled={@typing || @input == ""}
                  style="flex-shrink:0;"
                >
                  {if @typing, do: "…", else: "Send"}
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>

      <%!-- Non-chat tabs --%>
      <div
        :if={@active_tab_id != "chat"}
        class="j-shell"
        style="padding-top:32px;padding-bottom:60px;"
      >
        <div :if={@active_tab_id == "activity"}>
          <JargaAdminWeb.JargaComponents.activity_feed events={@activity_events} />
        </div>

        <div :if={@active_tab_id not in ["chat", "activity"]}>
          <div :if={current_tab_spec(@tabs, @active_tab_id) == nil} class="j-empty-state">
            <p class="j-empty-heading">Loading…</p>
          </div>

          <div :if={current_tab_spec(@tabs, @active_tab_id) != nil}>
            <div
              :for={comp <- Renderer.render_spec(current_tab_spec(@tabs, @active_tab_id))}
              style="margin-bottom:20px;"
            >
              {render_component(comp, assigns)}
            </div>
          </div>
        </div>
      </div>
    </div>

    <%!-- Footer — matches .inner-footer from cinematic-pages.css --%>
    <footer class="j-footer">
      <div class="j-footer-inner">
        <span class="j-footer-wordmark">JARGA</span>
        <nav class="j-footer-links">
          <a href="https://jargacommerce.com" class="j-footer-link" target="_blank">Commerce</a>
          <a href="https://jargacommerce.com/platform.html" class="j-footer-link" target="_blank">
            Platform
          </a>
          <a href="https://jargacommerce.com/plans.html" class="j-footer-link" target="_blank">
            Plans
          </a>
        </nav>
        <span class="j-footer-copy">© 2026 Jarga Commerce</span>
      </div>
    </footer>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Component renderer (inside LiveView)
  # ──────────────────────────────────────────────────────────────────────────

  defp render_component(%{type: :metric_grid, assigns: a}, _outer) do
    JargaAdminWeb.JargaComponents.metric_grid(a)
  end

  defp render_component(%{type: :metric_card, assigns: a}, _outer) do
    JargaAdminWeb.JargaComponents.metric_card(a)
  end

  defp render_component(%{type: :data_table, assigns: a}, _outer) do
    JargaAdminWeb.JargaComponents.data_table(a)
  end

  defp render_component(%{type: :detail_card, assigns: a}, _outer) do
    JargaAdminWeb.JargaComponents.detail_card(a)
  end

  defp render_component(%{type: :chart, assigns: a}, _outer) do
    JargaAdminWeb.JargaComponents.chart(a)
  end

  defp render_component(%{type: :alert_banner, assigns: a}, _outer) do
    JargaAdminWeb.JargaComponents.alert_banner(a)
  end

  defp render_component(%{type: :dynamic_form, assigns: a}, _outer) do
    JargaAdminWeb.JargaComponents.dynamic_form(a)
  end

  defp render_component(%{type: :empty_state, assigns: a}, _outer) do
    JargaAdminWeb.JargaComponents.empty_state(a)
  end

  defp render_component(%{type: :unknown, assigns: %{raw: raw}}, _outer) do
    Phoenix.HTML.raw(
      "<pre style='font-size:0.75rem;overflow:auto;'>#{Jason.encode!(raw, pretty: true)}</pre>"
    )
  end

  defp render_component(_, _), do: Phoenix.HTML.raw("")

  # ──────────────────────────────────────────────────────────────────────────
  # Event handlers
  # ──────────────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("send_message", %{"message" => ""}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    msg = %{role: "user", content: message, id: unique_id()}

    socket =
      socket
      |> update(:messages, &(&1 ++ [msg]))
      |> assign(:input, "")
      |> assign(:typing, true)
      |> assign(:streaming_text, "")
      |> assign(:rendered_components, [])

    # Send to Quecto (mock in dev)
    Task.start(fn ->
      MockBridge.send_message(@session_id, message)
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_input", params, socket) do
    {:noreply, assign(socket, :input, Map.get(params, "message", ""))}
  end

  @impl true
  def handle_event("use_suggestion", %{"text" => text}, socket) do
    {:noreply, assign(socket, :input, text)}
  end

  @impl true
  def handle_event("switch_tab", %{"id" => tab_id}, socket) do
    tabs = TabStore.list()
    tab = find_tab(tabs, tab_id)
    components = if tab, do: Renderer.render_spec(tab.ui_spec), else: []

    # Schedule refresh if tab has an interval
    if tab && tab.refresh_interval != :off do
      schedule_tab_refresh(tab_id, tab.refresh_interval)
    end

    {:noreply,
     socket
     |> assign(:active_tab_id, tab_id)
     |> assign(:tabs, tabs)
     |> assign(:rendered_components, components)
     |> assign(:context_menu, nil)}
  end

  @impl true
  def handle_event("show_context_menu", %{"id" => tab_id}, socket) do
    # Position near button — simplified (real impl uses JS hook for coords)
    {:noreply, assign(socket, :context_menu, %{tab_id: tab_id, x: 200, y: 100})}
  end

  @impl true
  def handle_event("close_context_menu", _, socket) do
    {:noreply, assign(socket, :context_menu, nil)}
  end

  @impl true
  def handle_event("start_rename", %{"id" => tab_id}, socket) do
    current_label =
      case TabStore.get(tab_id) do
        {:ok, tab} -> tab.label
        _ -> ""
      end

    {:noreply,
     socket
     |> assign(:rename_tab_id, tab_id)
     |> assign(:rename_value, current_label)
     |> assign(:context_menu, nil)}
  end

  @impl true
  def handle_event("confirm_rename", %{"tab_id" => id, "label" => label}, socket) do
    TabStore.rename(id, label)

    {:noreply,
     socket
     |> assign(:tabs, TabStore.list())
     |> assign(:rename_tab_id, nil)}
  end

  @impl true
  def handle_event("cancel_rename", _, socket) do
    {:noreply, assign(socket, :rename_tab_id, nil)}
  end

  @impl true
  def handle_event("duplicate_tab", %{"id" => id}, socket) do
    TabStore.duplicate(id)
    {:noreply, socket |> assign(:tabs, TabStore.list()) |> assign(:context_menu, nil)}
  end

  @impl true
  def handle_event("unpin_tab", %{"id" => id}, socket) do
    TabStore.unpin(id)
    tabs = TabStore.list()

    new_active =
      if socket.assigns.active_tab_id == id, do: "chat", else: socket.assigns.active_tab_id

    {:noreply,
     socket
     |> assign(:tabs, tabs)
     |> assign(:active_tab_id, new_active)
     |> assign(:context_menu, nil)}
  end

  @impl true
  def handle_event("toggle_chat", _, socket) do
    {:noreply, assign(socket, :chat_open, !socket.assigns.chat_open)}
  end

  @impl true
  def handle_event("reorder_tabs", %{"ids" => ids}, socket) do
    TabStore.reorder(ids)
    {:noreply, assign(socket, :tabs, TabStore.list())}
  end

  @impl true
  def handle_event("show_pin_modal", _, socket) do
    {:noreply, assign(socket, :pin_modal, true)}
  end

  @impl true
  def handle_event("cancel_pin", _, socket) do
    {:noreply, assign(socket, :pin_modal, false)}
  end

  @impl true
  def handle_event("confirm_pin", %{"label" => label, "icon" => icon}, socket) do
    # Pin current rendered components as a tab
    current_spec = components_to_spec(socket.assigns.rendered_components)
    TabStore.pin(label, icon, current_spec)

    {:noreply,
     socket
     |> assign(:tabs, TabStore.list())
     |> assign(:pin_modal, false)}
  end

  @impl true
  def handle_event("sort", %{"key" => _key}, socket) do
    # DataTable column sort — re-sort rendered components
    {:noreply, socket}
  end

  @impl true
  def handle_event("approve_action", %{"id" => _id}, socket) do
    # Forward approval to Quecto bridge
    {:noreply, socket}
  end

  @impl true
  def handle_event("reject_action", %{"id" => _id}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("submit_form", params, socket) do
    # Handle dynamic form submissions — call Jarga API
    _result = JargaAdmin.Api.post("/v1/pim/products", Map.delete(params, "_csrf_token"))
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_form", _, socket) do
    {:noreply, assign(socket, :rendered_components, [])}
  end

  # ──────────────────────────────────────────────────────────────────────────
  # PubSub / Info handlers
  # ──────────────────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:chunk, text}, socket) do
    {:noreply, update(socket, :streaming_text, &(&1 <> text))}
  end

  @impl true
  def handle_info(:done, socket) do
    # Finalise the streamed message
    full_text = socket.assigns.streaming_text
    clean_text = UiSpec.strip_spec(full_text)
    msg = %{role: "agent", content: clean_text, id: unique_id()}

    socket =
      socket
      |> update(:messages, &(&1 ++ [msg]))
      |> assign(:streaming_text, "")
      |> assign(:typing, false)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:activity, event}, socket) do
    {:noreply, update(socket, :activity_events, &(&1 ++ [event]))}
  end

  @impl true
  def handle_info({:ui_spec, spec}, socket) do
    components = Renderer.render_spec(spec)
    {:noreply, assign(socket, :rendered_components, components)}
  end

  @impl true
  def handle_info(:auto_refresh, socket) do
    schedule_auto_refresh()
    # Refresh current tab if it has a refresh interval
    tab = find_tab(socket.assigns.tabs, socket.assigns.active_tab_id)

    if tab && tab.refresh_interval != :off && tab.id != "chat" do
      # In a real implementation, re-fetch data and update the spec
      tabs = TabStore.list()
      components = Renderer.render_spec(tab.ui_spec)
      {:noreply, socket |> assign(:tabs, tabs) |> assign(:rendered_components, components)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:tab_refresh, tab_id}, socket) do
    if socket.assigns.active_tab_id == tab_id do
      tabs = TabStore.list()
      tab = find_tab(tabs, tab_id)
      components = if tab, do: Renderer.render_spec(tab.ui_spec), else: []
      {:noreply, socket |> assign(:tabs, tabs) |> assign(:rendered_components, components)}
    else
      {:noreply, socket}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Private helpers
  # ──────────────────────────────────────────────────────────────────────────

  defp find_tab(tabs, id) do
    Enum.find(tabs, &(&1.id == id))
  end

  defp current_tab_spec(tabs, tab_id) do
    case find_tab(tabs, tab_id) do
      nil -> nil
      tab -> tab.ui_spec
    end
  end

  defp schedule_auto_refresh do
    Process.send_after(self(), :auto_refresh, 30_000)
  end

  defp schedule_tab_refresh(tab_id, interval_secs) when is_integer(interval_secs) do
    Process.send_after(self(), {:tab_refresh, tab_id}, interval_secs * 1000)
  end

  defp schedule_tab_refresh(_, _), do: :ok

  defp unique_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

  defp suggestions do
    [
      "Show me today's orders",
      "How are sales trending?",
      "Which products are low on stock?",
      "Show me a store overview",
      "Create a new product"
    ]
  end

  defp components_to_spec(components) do
    raw =
      Enum.map(components, fn %{type: type, assigns: assigns} ->
        %{"type" => to_string(type), "data" => assigns}
      end)

    %{"layout" => "full", "components" => raw}
  end

  defp md_to_html(text) do
    case Earmark.as_html(text) do
      {:ok, html, _} -> html
      {:error, _, _} -> Phoenix.HTML.html_escape(text) |> Phoenix.HTML.safe_to_string()
    end
  end
end
