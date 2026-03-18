defmodule JargaAdminWeb.ChatLive do
  @moduledoc """
  Main chat + generative UI LiveView (Issue #19, #20, #23, #24).

  Layout:
  - Fixed nav + tab bar at top
  - Split: 40% chat pane (left), 60% rendered UI components (right)
  - Responsive: stacked on mobile

  Features:
  - Real-time streaming from Quecto agent
  - UI spec parsing + rendering in right pane
  - Pinned tabs with ETS persistence
  - Auto-refresh per tab
  - Context menus on tabs (rename, duplicate, unpin)
  """

  use JargaAdminWeb, :live_view

  alias JargaAdmin.{UiSpec, Renderer, TabStore, TabSpecBuilder, Api, DetailSpecBuilder}
  alias JargaAdmin.Quecto.Bridge
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
    active_tab = hd(tabs)
    # Build spec lazily on first access — never blocks Application.start/2
    active_spec = TabStore.get_or_build_spec(active_tab.id)

    socket =
      socket
      |> assign(:page_title, "Jarga Admin")
      |> assign(:messages, [])
      |> assign(:input, "")
      |> assign(:typing, false)
      |> assign(:streaming_text, "")
      |> assign(:tabs, TabStore.list())
      |> assign(:active_tab_id, active_tab.id)
      |> assign(:rendered_components, Renderer.render_spec(active_spec))
      |> assign(:activity_events, [])
      |> assign(:context_menu, nil)
      |> assign(:pin_modal, false)
      |> assign(:rename_tab_id, nil)
      |> assign(:rename_value, "")
      |> assign(:chat_open, false)
      |> assign(:view_menu, nil)
      |> assign(:move_modal, nil)
      |> assign(:menu_open, false)
      |> assign(:drawer_open, %{})
      # Detail panels
      |> assign(:detail, nil)
      # Toast notifications
      |> assign(:toasts, [])
      # Loading states — MapSet of tab IDs currently loading
      |> assign(:loading_tabs, MapSet.new())
      # Pagination — map of tab_id → current page (1-indexed)
      |> assign(:page_state, %{})
      # Sorting — map of tab_id → %{key: col_key, dir: :asc | :desc}
      |> assign(:sort_state, %{})
      # Confirmation dialog — nil or %{action: str, params: map, title: str, message: str}
      |> assign(:confirm_state, nil)
      # Search/filter state — map of tab_id → map of filter params (string keys)
      |> assign(:filter_state, %{})
      # Last-refreshed timestamps — map of tab_id → DateTime
      |> assign(:last_refreshed, %{})
      # Bulk selection — MapSet of selected item IDs
      |> assign(:selected_ids, MapSet.new())
      # Keyboard shortcuts modal — boolean toggle
      |> assign(:shortcuts_modal, false)

    {:ok, socket}
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Render
  # ── URL routing — handle_params ───────────────────────────────────────────

  @live_action_to_tab %{
    orders: "orders",
    products: "products",
    customers: "customers",
    promotions: "promotions",
    inventory: "inventory",
    analytics: "analytics",
    shipping: "shipping",
    draft_orders: "draft_orders",
    flows: "flows",
    audit: "audit",
    events: "events",
    collections: "collections",
    categories: "categories",
    metaobjects: "metaobjects",
    files: "files",
    tax: "tax",
    channels: "channels",
    webhooks: "webhooks",
    subscriptions: "subscriptions"
  }

  @impl true
  def handle_params(params, _uri, socket) do
    action = socket.assigns[:live_action] || :index
    tab_id = @live_action_to_tab[action]

    socket =
      if tab_id && tab_id != socket.assigns[:active_tab_id] do
        tabs = TabStore.list()
        spec = TabStore.get_or_build_spec(tab_id)

        socket
        |> assign(:active_tab_id, tab_id)
        |> assign(:tabs, tabs)
        |> assign(:detail, nil)
        |> assign(:rendered_components, Renderer.render_spec(spec))
      else
        socket
      end

    # Handle detail deep link params (e.g. /orders/:id, /products/:id)
    socket =
      case params do
        %{"id" => _id} ->
          # Detail views: id is available for deep-linked detail
          # (The actual fetch happens via view_order/view_product/etc. events)
          socket

        _ ->
          socket
      end

    {:noreply, socket}
  end

  # ──────────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Keyboard shortcuts listener --%>
    <div id="keyboard-shortcuts-hook" phx-hook="KeyboardShortcuts" class="hidden"></div>

    <%!-- Keyboard shortcuts modal --%>
    <%= if @shortcuts_modal do %>
      <div
        id="keyboard-shortcuts-modal"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
        phx-click="close_shortcuts_modal"
      >
        <div
          class="bg-white rounded-lg shadow-xl max-w-md w-full p-6"
          phx-click-away="close_shortcuts_modal"
        >
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-lg font-semibold">Keyboard shortcuts</h2>
            <button phx-click="close_shortcuts_modal" class="text-gray-400 hover:text-gray-600">
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>

          <div class="space-y-3 text-sm">
            <h3 class="font-medium text-gray-500 uppercase text-xs tracking-wide">Navigation</h3>
            <div class="flex justify-between"><span>Orders</span><kbd class="text-xs bg-gray-100 px-1.5 py-0.5 rounded">G then O</kbd></div>
            <div class="flex justify-between"><span>Products</span><kbd class="text-xs bg-gray-100 px-1.5 py-0.5 rounded">G then P</kbd></div>
            <div class="flex justify-between"><span>Customers</span><kbd class="text-xs bg-gray-100 px-1.5 py-0.5 rounded">G then C</kbd></div>
            <div class="flex justify-between"><span>Analytics</span><kbd class="text-xs bg-gray-100 px-1.5 py-0.5 rounded">G then A</kbd></div>
            <div class="flex justify-between"><span>Inventory</span><kbd class="text-xs bg-gray-100 px-1.5 py-0.5 rounded">G then I</kbd></div>

            <h3 class="font-medium text-gray-500 uppercase text-xs tracking-wide mt-4">Actions</h3>
            <div class="flex justify-between"><span>Refresh</span><kbd class="text-xs bg-gray-100 px-1.5 py-0.5 rounded">R</kbd></div>
            <div class="flex justify-between"><span>New item</span><kbd class="text-xs bg-gray-100 px-1.5 py-0.5 rounded">N</kbd></div>
            <div class="flex justify-between"><span>Close / Escape</span><kbd class="text-xs bg-gray-100 px-1.5 py-0.5 rounded">Esc</kbd></div>
            <div class="flex justify-between"><span>Show shortcuts</span><kbd class="text-xs bg-gray-100 px-1.5 py-0.5 rounded">?</kbd></div>
          </div>
        </div>
      </div>
    <% end %>

    <%!-- Toast notification stack --%>
    <JargaAdminWeb.JargaComponents.toast_container toasts={@toasts} />

    <%!-- Bulk action bar (shown when items are selected) --%>
    <JargaAdminWeb.JargaComponents.bulk_action_bar
      count={MapSet.size(@selected_ids)}
      type="item"
      actions={[
        %{label: "Archive", action: "archive", type: "product"},
        %{label: "Delete", action: "delete", type: "product", variant: :danger}
      ]}
    />

    <%!-- Confirmation dialog (destructive action gate) --%>
    <%= if @confirm_state do %>
      <JargaAdminWeb.JargaComponents.confirmation_dialog
        show={true}
        title={@confirm_state.title}
        message={@confirm_state.message}
        variant={@confirm_state.variant}
        confirm_label={@confirm_state.confirm_label}
      />
    <% else %>
      <JargaAdminWeb.JargaComponents.confirmation_dialog show={false} />
    <% end %>

    <%!-- Nav — Shopify-style with dropdowns --%>
    <nav class="j-nav">
      <%!-- Hamburger button — only visible on narrow screens --%>
      <button
        class="j-nav-burger"
        phx-click="toggle_menu"
        aria-label="Toggle navigation"
        aria-expanded={to_string(@menu_open)}
      >
        <span class={"j-nav-burger-icon #{if @menu_open, do: "open", else: ""}"}>
          <span /><span /><span />
        </span>
      </button>

      <%!-- Wordmark — centred on narrow, absolute-left on wide --%>
      <a href="/" class="j-wordmark">JARGA</a>

      <%!-- Wide nav inner row --%>
      <div class="j-nav-inner">
        <div class="j-nav-items">
          <.nav_section_item label="Orders" tab_id="orders">
            <div class="j-nav-dropdown-section">
              <button class="j-nav-dropdown-item" phx-click="switch_tab" phx-value-id="orders">
                All orders
              </button>
              <button
                class="j-nav-dropdown-item"
                phx-click="switch_tab"
                phx-value-id="draft_orders"
              >
                Draft orders
              </button>
              <button class="j-nav-dropdown-item">Abandoned checkouts</button>
              <button class="j-nav-dropdown-item">Returns</button>
            </div>
            <.saved_views_section views={saved_views_for(@tabs, "orders")} view_menu={@view_menu} />
          </.nav_section_item>

          <.nav_section_item label="Products" tab_id="products">
            <div class="j-nav-dropdown-section">
              <button class="j-nav-dropdown-item" phx-click="switch_tab" phx-value-id="products">
                All products
              </button>
              <button
                class="j-nav-dropdown-item"
                phx-click="switch_tab"
                phx-value-id="inventory"
              >
                Inventory
              </button>
              <button class="j-nav-dropdown-item">Collections</button>
              <button class="j-nav-dropdown-item">Gift cards</button>
            </div>
            <.saved_views_section views={saved_views_for(@tabs, "products")} view_menu={@view_menu} />
          </.nav_section_item>

          <.nav_section_item label="Customers" tab_id="customers">
            <div class="j-nav-dropdown-section">
              <button class="j-nav-dropdown-item" phx-click="switch_tab" phx-value-id="customers">
                All customers
              </button>
              <button class="j-nav-dropdown-item">Segments</button>
            </div>
            <.saved_views_section views={saved_views_for(@tabs, "customers")} view_menu={@view_menu} />
          </.nav_section_item>

          <.nav_section_item label="Analytics">
            <div class="j-nav-dropdown-section">
              <button
                class="j-nav-dropdown-item"
                phx-click="switch_tab"
                phx-value-id="analytics"
              >
                Overview
              </button>
              <button class="j-nav-dropdown-item">Reports</button>
              <button class="j-nav-dropdown-item">Live view</button>
            </div>
            <.saved_views_section views={saved_views_for(@tabs, "analytics")} view_menu={@view_menu} />
          </.nav_section_item>

          <.nav_section_item label="Marketing">
            <div class="j-nav-dropdown-section">
              <button class="j-nav-dropdown-item">Overview</button>
              <button
                class="j-nav-dropdown-item"
                phx-click="switch_tab"
                phx-value-id="promotions"
              >
                Campaigns
              </button>
              <button class="j-nav-dropdown-item">Automations</button>
            </div>
            <.saved_views_section views={saved_views_for(@tabs, "marketing")} view_menu={@view_menu} />
          </.nav_section_item>

          <.nav_section_item label="Discounts" tab_id="promotions">
            <div class="j-nav-dropdown-section">
              <button class="j-nav-dropdown-item" phx-click="switch_tab" phx-value-id="promotions">
                All discounts
              </button>
              <button class="j-nav-dropdown-item">Discount codes</button>
              <button class="j-nav-dropdown-item">Automatic discounts</button>
            </div>
            <.saved_views_section views={saved_views_for(@tabs, "discounts")} view_menu={@view_menu} />
          </.nav_section_item>

          <.nav_section_item label="Content">
            <div class="j-nav-dropdown-section">
              <button class="j-nav-dropdown-item">Files</button>
              <button class="j-nav-dropdown-item">Metaobjects</button>
              <button class="j-nav-dropdown-item">Menus</button>
              <button class="j-nav-dropdown-item">Pages</button>
              <button class="j-nav-dropdown-item">Blog posts</button>
            </div>
            <.saved_views_section views={saved_views_for(@tabs, "content")} view_menu={@view_menu} />
          </.nav_section_item>
        </div>
      </div>

      <%!-- Profile circle — absolutely pinned to far right of nav at all widths --%>
      <div class="j-nav-right">
        <div class="j-nav-avatar">JA</div>
      </div>
    </nav>

    <%!-- Mobile drawer — slides down from nav on narrow screens --%>
    <div class={"j-nav-drawer #{if @menu_open, do: "open", else: ""}"} id="nav-drawer">
      <div class="j-nav-drawer-inner">
        <.drawer_section label="Orders" open={Map.get(@drawer_open, "orders", false)} section="orders">
          <button class="j-drawer-item" phx-click="switch_tab" phx-value-id="orders">
            All orders
          </button>
          <button class="j-drawer-item" phx-click="switch_tab" phx-value-id="draft_orders">
            Draft orders
          </button>
          <button class="j-drawer-item">Abandoned checkouts</button>
          <button class="j-drawer-item">Returns</button>
        </.drawer_section>

        <.drawer_section
          label="Products"
          open={Map.get(@drawer_open, "products", false)}
          section="products"
        >
          <button class="j-drawer-item" phx-click="switch_tab" phx-value-id="products">
            All products
          </button>
          <button class="j-drawer-item" phx-click="switch_tab" phx-value-id="inventory">
            Inventory
          </button>
          <button class="j-drawer-item">Collections</button>
          <button class="j-drawer-item">Gift cards</button>
        </.drawer_section>

        <.drawer_section
          label="Customers"
          open={Map.get(@drawer_open, "customers", false)}
          section="customers"
        >
          <button class="j-drawer-item" phx-click="switch_tab" phx-value-id="customers">
            All customers
          </button>
          <button class="j-drawer-item">Segments</button>
        </.drawer_section>

        <.drawer_section
          label="Analytics"
          open={Map.get(@drawer_open, "analytics", false)}
          section="analytics"
        >
          <button class="j-drawer-item" phx-click="switch_tab" phx-value-id="analytics">
            Overview
          </button>
          <button class="j-drawer-item">Reports</button>
          <button class="j-drawer-item">Live view</button>
        </.drawer_section>

        <.drawer_section
          label="Marketing"
          open={Map.get(@drawer_open, "marketing", false)}
          section="marketing"
        >
          <button class="j-drawer-item">Overview</button>
          <button class="j-drawer-item" phx-click="switch_tab" phx-value-id="promotions">
            Campaigns
          </button>
          <button class="j-drawer-item">Automations</button>
        </.drawer_section>

        <.drawer_section
          label="Discounts"
          open={Map.get(@drawer_open, "discounts", false)}
          section="discounts"
        >
          <button class="j-drawer-item" phx-click="switch_tab" phx-value-id="promotions">
            All discounts
          </button>
          <button class="j-drawer-item">Discount codes</button>
          <button class="j-drawer-item">Automatic discounts</button>
        </.drawer_section>

        <.drawer_section
          label="Shipping"
          open={Map.get(@drawer_open, "shipping", false)}
          section="shipping"
        >
          <button class="j-drawer-item" phx-click="switch_tab" phx-value-id="shipping">
            Zones and rates
          </button>
          <button class="j-drawer-item">Carriers</button>
        </.drawer_section>

        <.drawer_section
          label="Content"
          open={Map.get(@drawer_open, "content", false)}
          section="content"
        >
          <button class="j-drawer-item">Files</button>
          <button class="j-drawer-item">Pages</button>
          <button class="j-drawer-item">Blog posts</button>
        </.drawer_section>
      </div>
    </div>

    <%!-- Save-view modal — nav-section picker --%>
    <div :if={@pin_modal} class="j-dialog-overlay" phx-click-away="cancel_pin">
      <div class="j-dialog">
        <p class="j-dialog-title">Save view</p>
        <p class="j-dialog-sub">Choose a name and where to add this view in the nav.</p>
        <form phx-submit="confirm_pin" class="j-dialog-form">
          <div>
            <label class="j-form-label">View name</label>
            <input
              name="label"
              class="j-input"
              placeholder="e.g. Low stock items"
              autofocus
            />
          </div>
          <div>
            <label class="j-form-label">Add to nav section</label>
            <select name="nav_section" class="j-input">
              <option value="orders">Orders</option>
              <option value="products">Products</option>
              <option value="customers">Customers</option>
              <option value="finances">Finances</option>
              <option value="analytics">Analytics</option>
              <option value="marketing">Marketing</option>
              <option value="discounts">Discounts</option>
              <option value="content">Content</option>
            </select>
          </div>
          <input type="hidden" name="icon" value="" />
          <div class="j-dialog-actions">
            <button type="submit" class="j-btn j-btn-solid j-btn-sm">Save view</button>
            <button type="button" class="j-btn j-btn-ghost j-btn-sm" phx-click="cancel_pin">
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>

    <%!-- Rename saved view modal --%>
    <div :if={@rename_tab_id} class="j-dialog-overlay" phx-click-away="cancel_rename">
      <div class="j-dialog">
        <p class="j-dialog-title">Rename view</p>
        <form phx-submit="confirm_rename" class="j-dialog-form">
          <input type="hidden" name="tab_id" value={@rename_tab_id} />
          <div>
            <label class="j-form-label">Name</label>
            <input name="label" class="j-input" value={@rename_value} autofocus />
          </div>
          <div class="j-dialog-actions">
            <button type="submit" class="j-btn j-btn-solid j-btn-sm">Save</button>
            <button type="button" class="j-btn j-btn-ghost j-btn-sm" phx-click="cancel_rename">
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>

    <%!-- Move saved view modal --%>
    <div :if={@move_modal} class="j-dialog-overlay" phx-click-away="cancel_move">
      <div class="j-dialog">
        <p class="j-dialog-title">Move view</p>
        <p class="j-dialog-sub">Choose which nav section to move this view to.</p>
        <form phx-submit="confirm_move" class="j-dialog-form">
          <input type="hidden" name="tab_id" value={@move_modal} />
          <div>
            <label class="j-form-label">Nav section</label>
            <select name="nav_section" class="j-input">
              <option value="orders">Orders</option>
              <option value="products">Products</option>
              <option value="customers">Customers</option>
              <option value="finances">Finances</option>
              <option value="analytics">Analytics</option>
              <option value="marketing">Marketing</option>
              <option value="discounts">Discounts</option>
              <option value="content">Content</option>
            </select>
          </div>
          <div class="j-dialog-actions">
            <button type="submit" class="j-btn j-btn-solid j-btn-sm">Move</button>
            <button type="button" class="j-btn j-btn-ghost j-btn-sm" phx-click="cancel_move">
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>

    <%!-- Page --%>
    <div class="j-page">
      <div class="j-tab-page">
        <%!-- Detail panel overrides everything else --%>
        <div :if={@detail} class="j-canvas-block">
          <.render_detail_panel detail={@detail} />
        </div>

        <%!-- AI-generated result — with Save view top-right --%>
        <div :if={!@detail && @rendered_components != []}>
          <div class="j-results-header">
            <button class="j-save-view-btn" phx-click="show_pin_modal">
              + Save view
            </button>
          </div>
          <div :for={comp <- @rendered_components} class="j-canvas-block">
            <.render_comp comp={comp} />
          </div>
        </div>

        <%!-- Default: active nav section content --%>
        <div :if={!@detail && @rendered_components == []}>
          <div class="j-tab-page-header">
            <p class="j-tab-page-label">
              {with tab <- find_tab(@tabs, @active_tab_id), do: tab && tab.label}
            </p>
            <%= if ts = Map.get(@last_refreshed, @active_tab_id) do %>
              <span class="j-tab-refresh-ts" title="Last refreshed">
                Updated {Calendar.strftime(ts, "%H:%M:%S")}
              </span>
            <% end %>
          </div>

          <div :if={@active_tab_id == "activity"}>
            <JargaAdminWeb.JargaComponents.activity_feed events={@activity_events} />
          </div>

          <div :if={@active_tab_id != "activity"}>
            <%!-- Loading spinner while spec is being fetched async --%>
            <div :if={MapSet.member?(@loading_tabs, @active_tab_id)} id="tab-loading-indicator">
              <JargaAdminWeb.JargaComponents.loading_spinner
                loading={true}
                label="Loading tab data…"
              />
            </div>
            <%!-- Spec not yet available and not loading — empty state --%>
            <div
              :if={
                !MapSet.member?(@loading_tabs, @active_tab_id) &&
                  current_tab_spec(@tabs, @active_tab_id) == nil
              }
              class="j-empty-state"
            >
              <p class="j-empty-heading">No data</p>
            </div>
            <div :if={
              !MapSet.member?(@loading_tabs, @active_tab_id) &&
                current_tab_spec(@tabs, @active_tab_id) != nil
            }>
              <div
                :for={comp <- Renderer.render_spec(current_tab_spec(@tabs, @active_tab_id))}
                class="j-canvas-block"
              >
                <.render_comp comp={comp} />
              </div>
            </div>
          </div>
        </div>
      </div>

      <footer class="j-footer">
        <div class="j-footer-inner">
          <span class="j-footer-wordmark">JARGA</span>
          <nav class="j-footer-links">
            <a href="https://jargacommerce.com" class="j-footer-link" target="_blank">Commerce</a>
            <a
              href="https://jargacommerce.com/platform.html"
              class="j-footer-link"
              target="_blank"
            >
              Platform
            </a>
            <a href="https://jargacommerce.com/plans.html" class="j-footer-link" target="_blank">
              Plans
            </a>
          </nav>
          <span class="j-footer-copy">© 2026 Jarga Commerce</span>
        </div>
      </footer>
    </div>

    <%!-- Chat FAB + popover — always present, hover-to-open --%>
    <div
      id="chat-popover"
      class={"j-chat-popover #{if @chat_open, do: "open", else: ""}"}
      phx-hook="ChatHover"
    >
      <%!-- FAB circle — shown when collapsed --%>
      <button class="j-chat-fab" phx-click="open_chat" aria-label="Open Jarga AI">
        <img
          src="/images/jarga-logo.svg"
          class="j-chat-fab-logo"
          alt="J"
          aria-hidden="true"
        />
        <span :if={@typing} class="j-chat-fab-dot" />
      </button>

      <%!-- Panel header — shown when open --%>
      <button class="j-chat-popover-header" phx-click="toggle_chat" aria-label="Close chat">
        <span class="j-chat-popover-title">
          Jarga <span :if={@typing} class="j-chat-status-dot"></span>
        </span>
        <span class="j-chat-popover-chevron">−</span>
      </button>

      <%!-- Panel body --%>
      <div class="j-chat-popover-body">
        <div class="j-chat-area" id="chat-messages" phx-hook="AutoScroll">
          <div :if={@messages == []} class="j-chat-welcome">
            <p class="j-chat-welcome-heading">What would you like to do?</p>
            <div class="j-suggestions">
              <button
                :for={s <- suggestions()}
                class="j-suggestion"
                phx-click="use_suggestion"
                phx-value-text={s}
              >
                {s}
              </button>
            </div>
          </div>

          <div :for={msg <- @messages} class={"j-bubble-wrap #{msg.role}"}>
            <div class={"j-bubble #{msg.role}"}>
              <span :if={msg.role == "user"}>{msg.content}</span>
              <span :if={msg.role == "agent"}>
                {Phoenix.HTML.raw(md_to_html(msg.content))}
              </span>
            </div>
          </div>

          <div :if={@streaming_text != "" || @typing} class="j-bubble-wrap agent">
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

        <div class="j-chat-input-wrap">
          <form phx-submit="send_message" phx-change="update_input" id="chat-form">
            <div class="j-chat-input-row">
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
              >
                {if @typing, do: "…", else: "Send"}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Component renderer (inside LiveView)
  # ──────────────────────────────────────────────────────────────────────────

  # ── HEEx component dispatcher (proper Phoenix components, not plain fn calls) ──

  attr :comp, :map, required: true

  defp render_comp(%{comp: %{type: :metric_grid, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)
    ~H"<JargaAdminWeb.JargaComponents.metric_grid metrics={@metrics} />"
  end

  defp render_comp(%{comp: %{type: :metric_card, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)
    ~H"<JargaAdminWeb.JargaComponents.metric_card
  label={@label}
  value={@value}
  trend={@trend}
  subtitle={assigns[:subtitle]}
/>"
  end

  defp render_comp(%{comp: %{type: :data_table, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)

    ~H"""
    <JargaAdminWeb.JargaComponents.data_table
      id={@id}
      title={assigns[:title]}
      columns={@columns}
      rows={@rows}
      actions={@actions}
      on_row_click={assigns[:on_row_click]}
      sort_key={@sort_key}
      sort_dir={@sort_dir}
      on_sort={assigns[:on_sort]}
      empty_message={assigns[:empty_message] || "No data to display"}
    />
    """
  end

  defp render_comp(%{comp: %{type: :detail_card, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)

    ~H"""
    <JargaAdminWeb.JargaComponents.detail_card
      title={@title}
      pairs={@pairs}
      timeline={@timeline}
      actions={@actions}
    />
    """
  end

  defp render_comp(%{comp: %{type: :chart, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)

    ~H"""
    <JargaAdminWeb.JargaComponents.chart
      id={@id}
      title={assigns[:title]}
      type={@type}
      labels={@labels}
      datasets={@datasets}
      height={assigns[:height] || 280}
    />
    """
  end

  defp render_comp(%{comp: %{type: :alert_banner, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)
    ~H"<JargaAdminWeb.JargaComponents.alert_banner
  kind={@kind}
  title={assigns[:title]}
  message={@message}
  retry_event={assigns[:retry_event]}
/>"
  end

  defp render_comp(%{comp: %{type: :dynamic_form, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)

    ~H"""
    <JargaAdminWeb.JargaComponents.dynamic_form
      id={@id}
      title={assigns[:title]}
      fields={@fields}
      values={@values}
      submit_event={@submit_event}
      cancel_event={@cancel_event}
    />
    """
  end

  defp render_comp(%{comp: %{type: :empty_state, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)
    ~H"<JargaAdminWeb.JargaComponents.empty_state
  icon={assigns[:icon]}
  title={@title}
  message={assigns[:message]}
/>"
  end

  defp render_comp(%{comp: %{type: :search_bar, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)

    ~H"""
    <JargaAdminWeb.JargaComponents.search_bar
      tab_id={@tab_id}
      placeholder={@placeholder}
      value={@value}
      filters={@filters}
    />
    """
  end

  defp render_comp(%{comp: %{type: :action_bar, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)
    ~H"<JargaAdminWeb.JargaComponents.action_bar actions={@actions} />"
  end

  defp render_comp(%{comp: %{type: :pagination, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)

    ~H"""
    <JargaAdminWeb.JargaComponents.pagination
      page={@page}
      per_page={@per_page}
      total_items={assigns[:total]}
      total_pages={assigns[:total_pages]}
    />
    """
  end

  defp render_comp(%{comp: %{type: :stat_bar, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)
    ~H"<JargaAdminWeb.JargaComponents.stat_bar stats={@stats} />"
  end

  defp render_comp(%{comp: %{type: :product_grid, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)

    ~H"""
    <JargaAdminWeb.JargaComponents.product_grid
      title={assigns[:title]}
      products={@products}
      on_click={assigns[:on_click] || "view_product"}
    />
    """
  end

  defp render_comp(%{comp: %{type: :order_detail, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)
    ~H"<JargaAdminWeb.JargaComponents.order_detail order={@order} />"
  end

  defp render_comp(%{comp: %{type: :product_detail, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)
    ~H"<JargaAdminWeb.JargaComponents.product_detail product={@product} />"
  end

  defp render_comp(%{comp: %{type: :customer_detail, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)

    ~H"""
    <JargaAdminWeb.JargaComponents.customer_detail
      customer={@customer}
      recent_orders={@recent_orders}
    />
    """
  end

  defp render_comp(%{comp: %{type: :promotion_list, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)
    ~H"<JargaAdminWeb.JargaComponents.promotion_list title={@title} promotions={@promotions} />"
  end

  defp render_comp(%{comp: %{type: :inventory_table, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)

    ~H"""
    <JargaAdminWeb.JargaComponents.inventory_table
      title={@title}
      rows={@rows}
      on_restock={assigns[:on_restock]}
    />
    """
  end

  defp render_comp(%{comp: %{type: :inventory_detail_table, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)

    ~H"""
    <JargaAdminWeb.JargaComponents.inventory_detail_table
      title={assigns[:title]}
      rows={@rows}
    />
    """
  end

  defp render_comp(%{comp: %{type: :analytics_revenue, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)

    ~H"""
    <JargaAdminWeb.JargaComponents.analytics_revenue
      title={assigns[:title]}
      rows={@rows}
    />
    """
  end

  defp render_comp(%{comp: %{type: :analytics_breakdown, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)

    ~H"""
    <JargaAdminWeb.JargaComponents.analytics_breakdown
      title={assigns[:title]}
      rows={@rows}
    />
    """
  end

  defp render_comp(%{comp: %{type: :shipping_zones_table, assigns: a}} = assigns) do
    assigns = Map.merge(assigns, a)

    ~H"""
    <JargaAdminWeb.JargaComponents.shipping_zones_table
      title={assigns[:title]}
      zones={@zones}
    />
    """
  end

  defp render_comp(%{comp: %{type: :unknown, assigns: %{raw: raw}}} = assigns) do
    assigns = assign(assigns, :raw_json, Jason.encode!(raw, pretty: true))

    ~H"""
    <pre style="font-size:0.75rem;overflow:auto;">{@raw_json}</pre>
    """
  end

  defp render_comp(assigns) do
    _ = assigns
    ~H""
  end

  # ── Detail panel (order / product / customer) ─────────────────────────────

  attr :detail, :map, required: true

  defp render_detail_panel(%{detail: %{type: :order, data: order}} = assigns) do
    assigns = assign(assigns, :order, order)
    ~H"<JargaAdminWeb.JargaComponents.order_detail order={@order} />"
  end

  defp render_detail_panel(%{detail: %{type: :product, data: product}} = assigns) do
    assigns = assign(assigns, :product, product)
    ~H"<JargaAdminWeb.JargaComponents.product_detail product={@product} />"
  end

  defp render_detail_panel(%{detail: %{type: :customer, data: customer}} = assigns) do
    recent =
      case Api.list_orders() do
        {:ok, %{"items" => items}} -> Enum.filter(items, &(&1["customer_id"] == customer["id"]))
        _ -> []
      end

    assigns = assigns |> assign(:customer, customer) |> assign(:recent_orders, recent)
    ~H"<JargaAdminWeb.JargaComponents.customer_detail
  customer={@customer}
  recent_orders={@recent_orders}
/>"
  end

  defp render_detail_panel(assigns) do
    _ = assigns
    ~H""
  end

  # ── Wide-nav section item (label + hover dropdown) ────────────────────────

  attr :label, :string, required: true
  attr :tab_id, :string, default: nil
  slot :inner_block, required: true

  defp nav_section_item(assigns) do
    ~H"""
    <div class="j-nav-item">
      <button class="j-nav-link">
        {@label} <span class="j-nav-link-caret">▼</span>
      </button>
      <div class="j-nav-dropdown">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ── Mobile drawer accordion section ───────────────────────────────────────

  attr :label, :string, required: true
  attr :section, :string, required: true
  attr :open, :boolean, default: false
  slot :inner_block, required: true

  defp drawer_section(assigns) do
    ~H"""
    <div class="j-drawer-section">
      <button
        class={"j-drawer-heading #{if @open, do: "open", else: ""}"}
        phx-click="toggle_drawer"
        phx-value-section={@section}
      >
        {@label}
        <span class="j-drawer-caret">{if @open, do: "−", else: "+"}</span>
      </button>
      <div class={"j-drawer-items #{if @open, do: "open", else: ""}"}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ── Saved-views dropdown section with inline 3-dot menu ───────────────────

  attr :views, :list, required: true
  attr :view_menu, :any, default: nil

  defp saved_views_section(%{views: []} = assigns) do
    _ = assigns
    ~H""
  end

  defp saved_views_section(assigns) do
    ~H"""
    <div class="j-nav-dropdown-section">
      <div class="j-nav-dropdown-label">Saved views</div>
      <div :for={view <- @views} class="j-nav-saved-row">
        <button
          class="j-nav-dropdown-item j-nav-saved-label"
          phx-click="switch_tab"
          phx-value-id={view.id}
        >
          {view.label}
        </button>
        <div class="j-nav-saved-menu-wrap">
          <button
            class="j-nav-saved-dots"
            phx-click="toggle_view_menu"
            phx-value-id={view.id}
            title="View options"
          >
            ···
          </button>
          <div
            :if={@view_menu == view.id}
            class="j-nav-saved-popover"
            phx-click-away="close_view_menu"
          >
            <button
              class="j-nav-saved-popover-item"
              phx-click="start_rename_view"
              phx-value-id={view.id}
            >
              Rename
            </button>
            <button
              class="j-nav-saved-popover-item"
              phx-click="show_move_modal"
              phx-value-id={view.id}
            >
              Move to&hellip;
            </button>
            <button
              class="j-nav-saved-popover-item danger"
              phx-click="delete_view"
              phx-value-id={view.id}
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
      |> assign(:detail, nil)

    Task.start(fn ->
      Bridge.send_message(@session_id, message)
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

    # Check if spec is already cached (no loading needed)
    cached_spec =
      case TabStore.get(tab_id) do
        {:ok, %{ui_spec: spec}} when not is_nil(spec) -> spec
        _ -> nil
      end

    socket =
      socket
      |> assign(:active_tab_id, tab_id)
      |> assign(:tabs, tabs)
      |> assign(:context_menu, nil)
      |> assign(:detail, nil)
      |> assign(:menu_open, false)

    socket =
      if cached_spec do
        # Already cached — render immediately, no loading state
        assign(socket, :rendered_components, Renderer.render_spec(cached_spec))
      else
        # Needs API call — show loading state and build async
        Task.async(fn -> {tab_id, TabStore.get_or_build_spec(tab_id)} end)

        socket
        |> assign(:rendered_components, [])
        |> update(:loading_tabs, &MapSet.put(&1, tab_id))
      end

    # Schedule refresh if tab has an interval
    if tab && tab.refresh_interval != :off do
      schedule_tab_refresh(tab_id, tab.refresh_interval)
    end

    # Push URL patch for deep linking (map tab_id to route)
    route = tab_id_to_route(tab_id)
    socket = if route, do: push_patch(socket, to: route), else: socket

    {:noreply, socket}
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

  # ── Saved-view 3-dot menu ──────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_view_menu", %{"id" => id}, socket) do
    current = socket.assigns.view_menu
    {:noreply, assign(socket, :view_menu, if(current == id, do: nil, else: id))}
  end

  @impl true
  def handle_event("close_view_menu", _, socket) do
    {:noreply, assign(socket, :view_menu, nil)}
  end

  @impl true
  def handle_event("start_rename_view", %{"id" => tab_id}, socket) do
    current_label =
      case TabStore.get(tab_id) do
        {:ok, tab} -> tab.label
        _ -> ""
      end

    {:noreply,
     socket
     |> assign(:rename_tab_id, tab_id)
     |> assign(:rename_value, current_label)
     |> assign(:view_menu, nil)}
  end

  @impl true
  def handle_event("show_move_modal", %{"id" => tab_id}, socket) do
    {:noreply,
     socket
     |> assign(:move_modal, tab_id)
     |> assign(:view_menu, nil)}
  end

  @impl true
  def handle_event("cancel_move", _, socket) do
    {:noreply, assign(socket, :move_modal, nil)}
  end

  @impl true
  def handle_event("confirm_move", %{"tab_id" => id, "nav_section" => section}, socket) do
    case TabStore.get(id) do
      {:ok, tab} ->
        updated_spec = Map.put(tab.ui_spec || %{}, "nav_section", section)
        TabStore.update(id, %{ui_spec: updated_spec})

      _ ->
        :ok
    end

    {:noreply,
     socket
     |> assign(:tabs, TabStore.list())
     |> assign(:move_modal, nil)}
  end

  @impl true
  def handle_event("delete_view", %{"id" => id}, socket) do
    TabStore.unpin(id)
    tabs = TabStore.list()

    new_active =
      if socket.assigns.active_tab_id == id,
        do: hd(tabs).id,
        else: socket.assigns.active_tab_id

    {:noreply,
     socket
     |> assign(:tabs, tabs)
     |> assign(:active_tab_id, new_active)
     |> assign(:view_menu, nil)}
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
  def handle_event("toggle_menu", _, socket) do
    {:noreply, assign(socket, :menu_open, !socket.assigns.menu_open)}
  end

  @impl true
  def handle_event("toggle_drawer", %{"section" => section}, socket) do
    current = socket.assigns.drawer_open
    is_open = Map.get(current, section, false)
    {:noreply, assign(socket, :drawer_open, Map.put(current, section, !is_open))}
  end

  @impl true
  def handle_event("open_chat", _, socket) do
    {:noreply, assign(socket, :chat_open, true)}
  end

  @impl true
  def handle_event("close_chat", _, socket) do
    {:noreply, assign(socket, :chat_open, false)}
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
  def handle_event("confirm_pin", %{"label" => label, "icon" => icon} = params, socket) do
    current_spec = components_to_spec(socket.assigns.rendered_components)
    nav_section = Map.get(params, "nav_section", "")
    # Store nav_section in spec metadata so the nav dropdown can surface it
    spec = Map.put(current_spec, "nav_section", nav_section)
    TabStore.pin(label, icon, spec)

    {:noreply,
     socket
     |> assign(:tabs, TabStore.list())
     |> assign(:pin_modal, false)}
  end

  @impl true
  def handle_event("sort", %{"key" => key}, socket) do
    tab_id = socket.assigns.active_tab_id
    current = Map.get(socket.assigns.sort_state, tab_id, %{key: nil, dir: :asc})

    new_sort =
      if current.key == key do
        %{key: key, dir: toggle_dir(current.dir)}
      else
        %{key: key, dir: :asc}
      end

    new_sort_state = Map.put(socket.assigns.sort_state, tab_id, new_sort)

    sorted_components =
      apply_sort(socket.assigns.rendered_components, new_sort.key, new_sort.dir)

    {:noreply,
     socket
     |> assign(:sort_state, new_sort_state)
     |> assign(:rendered_components, sorted_components)}
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
    # Generic fallback — route via hidden _api_endpoint field if present
    clean = clean_form_params(params)

    socket =
      case Map.get(params, "_api_endpoint") do
        nil ->
          socket
          |> push_toast(:error, "Form has no API endpoint configured")

        endpoint ->
          case Api.post(endpoint, clean) do
            {:ok, _} -> socket |> push_toast(:success, "Saved successfully") |> clear_rendered()
            {:error, _} -> socket |> push_toast(:error, "Failed to save. Please try again.")
          end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_product", params, socket) do
    socket =
      case Api.create_product(clean_form_params(params)) do
        {:ok, _} ->
          socket
          |> push_toast(:success, "Product created successfully")
          |> clear_rendered()
          |> reload_tab_spec()

        {:error, err} ->
          socket |> push_toast(:error, api_error_message(err, "Failed to create product"))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_customer", params, socket) do
    socket =
      case Api.create_customer(clean_form_params(params)) do
        {:ok, _} ->
          socket
          |> push_toast(:success, "Customer created successfully")
          |> clear_rendered()
          |> reload_tab_spec()

        {:error, err} ->
          socket |> push_toast(:error, api_error_message(err, "Failed to create customer"))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_order", params, socket) do
    socket =
      case Api.post("/v1/oms/orders", clean_form_params(params)) do
        {:ok, _} ->
          socket
          |> push_toast(:success, "Order created successfully")
          |> clear_rendered()
          |> reload_tab_spec()

        {:error, err} ->
          socket |> push_toast(:error, api_error_message(err, "Failed to create order"))
      end

    {:noreply, socket}
  end

  # ── Promotion detail ──────────────────────────────────────────────────────

  @impl true
  def handle_event("view_promotion", %{"id" => promo_id}, socket) do
    socket =
      case Api.get_promotion(promo_id) do
        {:ok, promo} ->
          coupons =
            case Api.list_promotion_coupons(promo_id) do
              {:ok, %{"items" => items}} -> items
              {:ok, items} when is_list(items) -> items
              _ -> []
            end

          detail_spec = DetailSpecBuilder.build_promotion_spec(promo, coupons)

          socket
          |> assign(:rendered_components, Renderer.render_spec(detail_spec))
          |> assign(:detail, nil)

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Could not load promotion"))
      end

    {:noreply, socket}
  end

  def handle_event("view_promotion", _params, socket), do: {:noreply, socket}

  def handle_event("generate_coupons", params, socket) do
    campaign_id = Map.get(params, "_campaign_id", "")
    attrs = clean_form_params(Map.drop(params, ["_campaign_id"]))
    merged = Map.put(attrs, "campaign_id", campaign_id)

    socket =
      if campaign_id == "" do
        push_toast(socket, :error, "Campaign ID missing")
      else
        case Api.generate_coupons(merged) do
          {:ok, result} ->
            count = length(result["codes"] || [])

            socket
            |> push_toast(:success, "#{count} coupon codes generated")
            |> assign(:rendered_components, [])

          {:error, err} ->
            push_toast(socket, :error, api_error_message(err, "Failed to generate coupons"))
        end
      end

    {:noreply, socket}
  end

  def handle_event("publish_promotion", %{"id" => promo_id}, socket) do
    socket =
      case Api.publish_promotion(promo_id) do
        {:ok, _} ->
          push_toast(socket, :success, "Campaign published")

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to publish campaign"))
      end

    {:noreply, socket}
  end

  def handle_event("publish_promotion", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("create_promotion", params, socket) do
    socket =
      case Api.create_promotion(clean_form_params(params)) do
        {:ok, _} ->
          socket
          |> push_toast(:success, "Promotion created successfully")
          |> clear_rendered()
          |> reload_tab_spec()

        {:error, err} ->
          socket |> push_toast(:error, api_error_message(err, "Failed to create promotion"))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_product", params, socket) do
    product_id = Map.get(params, "_product_id")

    if is_nil(product_id) or product_id == "" do
      {:noreply, push_toast(socket, :error, "Missing product ID")}
    else
      attrs =
        params
        |> clean_form_params()
        |> Map.delete("_product_id")

      socket =
        case Api.update_product(product_id, attrs) do
          {:ok, updated} ->
            socket
            |> push_toast(:success, "Product updated successfully")
            |> assign(:rendered_components, [])
            |> assign(:detail, %{type: :product, data: updated})

          {:error, err} ->
            push_toast(socket, :error, api_error_message(err, "Failed to update product"))
        end

      {:noreply, socket}
    end
  end

  # ── Variant management ────────────────────────────────────────────────────

  def handle_event("add_variant", params, socket) do
    product_id = Map.get(params, "_product_id", "")
    attrs = clean_form_params(Map.drop(params, ["_product_id"]))

    socket =
      if product_id == "" do
        push_toast(socket, :error, "Product ID missing")
      else
        case Api.create_variant(product_id, attrs) do
          {:ok, _} ->
            socket
            |> push_toast(:success, "Variant added")
            |> assign(:rendered_components, [])

          {:error, err} ->
            push_toast(socket, :error, api_error_message(err, "Failed to add variant"))
        end
      end

    {:noreply, socket}
  end

  def handle_event("update_variant", params, socket) do
    variant_id = Map.get(params, "_variant_id", "")
    attrs = clean_form_params(Map.drop(params, ["_variant_id"]))

    socket =
      if variant_id == "" do
        push_toast(socket, :error, "Variant ID missing")
      else
        case Api.update_variant(variant_id, attrs) do
          {:ok, _} ->
            push_toast(socket, :success, "Variant updated")

          {:error, err} ->
            push_toast(socket, :error, api_error_message(err, "Failed to update variant"))
        end
      end

    {:noreply, socket}
  end

  def handle_event("delete_variant", %{"id" => variant_id}, socket) do
    socket =
      case Api.delete_variant(variant_id) do
        {:ok, _} ->
          push_toast(socket, :success, "Variant deleted")

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to delete variant"))
      end

    {:noreply, socket}
  end

  def handle_event("delete_variant", _params, socket), do: {:noreply, socket}

  def handle_event("generate_variants", %{"product_id" => product_id}, socket) do
    socket =
      case Api.generate_variants(product_id) do
        {:ok, result} ->
          count = result["variants_created"] || 0
          push_toast(socket, :success, "#{count} variant(s) generated")

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to generate variants"))
      end

    {:noreply, socket}
  end

  def handle_event("generate_variants", _params, socket), do: {:noreply, socket}

  # ── Shipping zone detail ──────────────────────────────────────────────────

  @impl true
  def handle_event("view_shipping_zone", %{"id" => zone_id}, socket) do
    socket =
      case Api.get_shipping_zone(zone_id) do
        {:ok, zone} ->
          rates =
            case Api.list_shipping_rates(zone_id) do
              {:ok, %{"items" => items}} -> items
              {:ok, items} when is_list(items) -> items
              _ -> []
            end

          detail_spec = DetailSpecBuilder.build_shipping_zone_spec(zone, rates)

          socket
          |> assign(:rendered_components, Renderer.render_spec(detail_spec))
          |> assign(:detail, nil)

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Could not load shipping zone"))
      end

    {:noreply, socket}
  end

  def handle_event("view_shipping_zone", _params, socket), do: {:noreply, socket}

  def handle_event("add_shipping_rate", params, socket) do
    zone_id = Map.get(params, "_zone_id", "")
    attrs = clean_form_params(Map.drop(params, ["_zone_id"]))

    socket =
      if zone_id == "" do
        push_toast(socket, :error, "Zone ID missing")
      else
        case Api.create_shipping_rate(zone_id, attrs) do
          {:ok, _} ->
            socket
            |> push_toast(:success, "Shipping rate added")
            |> assign(:rendered_components, [])

          {:error, err} ->
            push_toast(socket, :error, api_error_message(err, "Failed to add rate"))
        end
      end

    {:noreply, socket}
  end

  def handle_event("delete_shipping_zone", %{"id" => zone_id}, socket) do
    socket =
      case Api.delete_shipping_zone(zone_id) do
        {:ok, _} ->
          socket
          |> push_toast(:success, "Shipping zone deleted")
          |> assign(:rendered_components, [])
          |> reload_tab_spec()

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to delete zone"))
      end

    {:noreply, socket}
  end

  def handle_event("delete_shipping_zone", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("create_shipping_zone", params, socket) do
    socket =
      case Api.create_shipping_zone(clean_form_params(params)) do
        {:ok, _} ->
          socket
          |> push_toast(:success, "Shipping zone created successfully")
          |> clear_rendered()
          |> reload_tab_spec()

        {:error, err} ->
          socket |> push_toast(:error, api_error_message(err, "Failed to create shipping zone"))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_create_form", %{"resource" => resource}, socket) do
    spec = create_form_spec(resource)

    {:noreply,
     socket
     |> assign(:rendered_components, Renderer.render_spec(spec))
     |> assign(:detail, nil)}
  end

  def handle_event("show_create_form", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("cancel_form", _, socket) do
    {:noreply, assign(socket, :rendered_components, [])}
  end

  # ── Auth ──────────────────────────────────────────────────────────────────

  def handle_event("logout", _params, socket) do
    {:noreply, push_navigate(socket, to: "/login")}
  end

  # ── Bulk selection ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_ids, id) do
        MapSet.delete(socket.assigns.selected_ids, id)
      else
        MapSet.put(socket.assigns.selected_ids, id)
      end

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  @impl true
  def handle_event("select_all", %{"ids" => ids_json}, socket) do
    ids = Jason.decode!(ids_json)
    selected = Enum.reduce(ids, MapSet.new(), &MapSet.put(&2, &1))
    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_event("select_all", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("clear_selection", _, socket) do
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  @impl true
  def handle_event("bulk_action", %{"action" => action, "type" => type}, socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)

    results =
      Enum.map(ids, fn id ->
        case {action, type} do
          {"archive", "product"} -> Api.archive_product(id)
          {"delete", "product"} -> Api.delete_product(id)
          {"delete", "customer"} -> Api.delete_customer(id)
          {"fulfill", "order"} -> Api.create_fulfillment(id, %{})
          {"cancel", "order"} -> Api.cancel_order(id)
          _ -> {:error, "Unknown bulk action #{action}/#{type}"}
        end
      end)

    {successes, failures} = Enum.split_with(results, &match?({:ok, _}, &1))
    count = length(successes)
    fail_count = length(failures)

    socket =
      socket
      |> assign(:selected_ids, MapSet.new())
      |> then(fn s ->
        if count > 0 do
          push_toast(s, :success, "#{count} item(s) #{action}d successfully")
        else
          s
        end
      end)
      |> then(fn s ->
        if fail_count > 0 do
          push_toast(s, :error, "#{fail_count} item(s) failed to #{action}")
        else
          s
        end
      end)

    {:noreply, socket}
  end

  def handle_event("bulk_action", _params, socket), do: {:noreply, socket}

  # ── Confirmation dialog ────────────────────────────────────────────────────

  @impl true
  def handle_event("request_confirm", params, socket) do
    confirm = %{
      action: params["action"],
      params: Map.drop(params, ["action", "title", "message", "variant"]),
      title: params["title"] || "Are you sure?",
      message: params["message"] || "This action cannot be undone.",
      variant: if(params["variant"] == "normal", do: :normal, else: :destructive),
      confirm_label: params["confirm_label"] || "Confirm"
    }

    {:noreply, assign(socket, :confirm_state, confirm)}
  end

  @impl true
  def handle_event("cancel_confirm", _, socket) do
    {:noreply, assign(socket, :confirm_state, nil)}
  end

  @impl true
  def handle_event("confirm_action", _, socket) do
    case socket.assigns.confirm_state do
      nil ->
        {:noreply, socket}

      %{action: action, params: params} ->
        socket = assign(socket, :confirm_state, nil)
        handle_event(action, params, socket)
    end
  end

  def handle_event("cancel_order", %{"id" => order_id}, socket) do
    socket =
      case Api.cancel_order(order_id) do
        {:ok, _} ->
          socket_with_toast = push_toast(socket, :success, "Order cancelled")

          case Api.get_order(order_id) do
            {:ok, order} -> assign(socket_with_toast, :detail, %{type: :order, data: order})
            _ -> socket_with_toast
          end

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to cancel order"))
      end

    {:noreply, socket}
  end

  def handle_event("cancel_order", _params, socket), do: {:noreply, socket}

  def handle_event("add_order_note", params, socket) do
    order_id = Map.get(params, "_order_id", "")
    note = Map.get(params, "note", "")

    socket =
      if order_id == "" or note == "" do
        push_toast(socket, :error, "Order ID and note are required")
      else
        case Api.add_order_note(order_id, note) do
          {:ok, _} ->
            socket
            |> push_toast(:success, "Note added")
            |> assign(:rendered_components, [])

          {:error, err} ->
            push_toast(socket, :error, api_error_message(err, "Failed to add note"))
        end
      end

    {:noreply, socket}
  end

  def handle_event("retry_tab", _, socket) do
    {:noreply, reload_tab_spec(socket)}
  end

  def handle_event("next_page", _, socket) do
    tab_id = socket.assigns.active_tab_id
    current = Map.get(socket.assigns.page_state, tab_id, 1)
    socket = assign(socket, :page_state, Map.put(socket.assigns.page_state, tab_id, current + 1))
    {:noreply, reload_tab_spec(socket)}
  end

  def handle_event("prev_page", _, socket) do
    tab_id = socket.assigns.active_tab_id
    current = Map.get(socket.assigns.page_state, tab_id, 1)
    new_page = max(1, current - 1)
    socket = assign(socket, :page_state, Map.put(socket.assigns.page_state, tab_id, new_page))
    {:noreply, reload_tab_spec(socket)}
  end

  def handle_event("search", %{"q" => q} = params, socket) do
    tab_id = params["tab_id"] || socket.assigns.active_tab_id
    filters = Map.get(socket.assigns.filter_state, tab_id, %{})
    new_filters = Map.put(filters, "q", q)

    socket =
      assign(socket, :filter_state, Map.put(socket.assigns.filter_state, tab_id, new_filters))

    {:noreply, reload_tab_spec_for(socket, tab_id)}
  end

  def handle_event("set_filter", params, socket) do
    tab_id = params["tab_id"] || socket.assigns.active_tab_id
    filters = Map.get(socket.assigns.filter_state, tab_id, %{})

    new_filters =
      params
      |> Map.drop(["tab_id"])
      |> Enum.reduce(filters, fn {k, v}, acc ->
        if v == "" or v == nil, do: Map.delete(acc, k), else: Map.put(acc, k, v)
      end)

    socket =
      assign(socket, :filter_state, Map.put(socket.assigns.filter_state, tab_id, new_filters))

    {:noreply, reload_tab_spec_for(socket, tab_id)}
  end

  def handle_event("clear_filter", params, socket) do
    tab_id = params["tab_id"] || socket.assigns.active_tab_id
    socket = assign(socket, :filter_state, Map.put(socket.assigns.filter_state, tab_id, %{}))
    {:noreply, reload_tab_spec_for(socket, tab_id)}
  end

  def handle_event("go_to_page", %{"page" => page_str}, socket) do
    tab_id = socket.assigns.active_tab_id

    case Integer.parse(page_str) do
      {page, _} when page >= 1 ->
        socket =
          assign(socket, :page_state, Map.put(socket.assigns.page_state, tab_id, page))

        {:noreply, reload_tab_spec(socket)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("dismiss_toast", %{"id" => "all"}, socket) do
    {:noreply, assign(socket, :toasts, [])}
  end

  def handle_event("dismiss_toast", %{"id" => id}, socket) do
    {:noreply, update(socket, :toasts, fn toasts -> Enum.reject(toasts, &(&1.id == id)) end)}
  end

  # ── Drill-through: Orders ──────────────────────────────────────────────────

  @impl true
  def handle_event("view_order", %{"id" => order_id}, socket) do
    case Api.get_order(order_id) do
      {:ok, order} -> {:noreply, assign(socket, :detail, %{type: :order, data: order})}
      _ -> {:noreply, socket}
    end
  end

  # ── Drill-through: Products ────────────────────────────────────────────────

  @impl true
  def handle_event("view_product", %{"id" => product_id}, socket) do
    case Api.get_product(product_id) do
      {:ok, product} -> {:noreply, assign(socket, :detail, %{type: :product, data: product})}
      _ -> {:noreply, socket}
    end
  end

  # ── Media upload ──────────────────────────────────────────────────────────

  def handle_event("request_upload_url", params, socket) do
    attrs = %{
      filename: params["filename"] || "",
      content_type: params["content_type"] || "application/octet-stream",
      product_id: params["product_id"]
    }

    socket =
      case Api.get_upload_url(attrs) do
        {:ok, result} ->
          upload_url = result["upload_url"] || ""

          push_toast(
            socket,
            :success,
            "Upload URL ready — upload to: #{String.slice(upload_url, 0, 50)}…"
          )

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to get upload URL"))
      end

    {:noreply, socket}
  end

  def handle_event("delete_media", %{"id" => media_id}, socket) do
    socket =
      case Api.delete_media(media_id) do
        {:ok, _} ->
          push_toast(socket, :success, "Media deleted")

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to delete media"))
      end

    {:noreply, socket}
  end

  def handle_event("delete_media", _params, socket), do: {:noreply, socket}

  def handle_event("update_media_alt_text", params, socket) do
    media_id = Map.get(params, "_media_id", "")
    attrs = clean_form_params(Map.drop(params, ["_media_id"]))

    socket =
      if media_id == "" do
        push_toast(socket, :error, "Media ID missing")
      else
        case Api.update_media(media_id, attrs) do
          {:ok, _} ->
            push_toast(socket, :success, "Alt text updated")

          {:error, err} ->
            push_toast(socket, :error, api_error_message(err, "Failed to update media"))
        end
      end

    {:noreply, socket}
  end

  def handle_event("reorder_media", params, socket) do
    product_id = params["product_id"] || ""
    order = params["order"] |> Jason.decode!()

    socket =
      if product_id == "" do
        push_toast(socket, :error, "Product ID missing")
      else
        case Api.reorder_media(product_id, order) do
          {:ok, _} ->
            push_toast(socket, :success, "Media order saved")

          {:error, err} ->
            push_toast(socket, :error, api_error_message(err, "Failed to reorder media"))
        end
      end

    {:noreply, socket}
  end

  # ── Flows (automations) ───────────────────────────────────────────────────

  def handle_event("view_flow", %{"id" => flow_id}, socket) do
    socket =
      with {:ok, flow} <- Api.get_flow(flow_id),
           {:ok, runs} <- Api.list_flow_runs(flow_id) do
        run_rows =
          case runs do
            %{"items" => items} -> items
            items when is_list(items) -> items
            _ -> []
          end

        detail_spec = %{
          "components" => [
            %{
              "type" => "stat_bar",
              "data" => %{
                "stats" => [
                  %{"label" => "Flow", "value" => flow["name"] || flow_id},
                  %{"label" => "Status", "value" => flow["status"] || "—"},
                  %{"label" => "Trigger", "value" => flow["trigger"] || "—"},
                  %{"label" => "Total runs", "value" => "#{flow["run_count"] || 0}"}
                ]
              }
            },
            %{
              "type" => "action_bar",
              "data" => %{
                "actions" => [
                  %{
                    "label" => "Enable",
                    "event" => "toggle_flow",
                    "params" => %{"id" => flow_id, "action" => "enable"}
                  },
                  %{
                    "label" => "Disable",
                    "event" => "toggle_flow",
                    "params" => %{"id" => flow_id, "action" => "disable"}
                  },
                  %{
                    "label" => "Delete",
                    "event" => "delete_flow",
                    "params" => %{"id" => flow_id},
                    "variant" => "danger"
                  }
                ]
              }
            },
            %{
              "type" => "data_table",
              "title" => "Execution history",
              "data" => %{
                "columns" => [
                  %{"key" => "started_at", "label" => "Started"},
                  %{"key" => "status", "label" => "Status"},
                  %{"key" => "duration_ms", "label" => "Duration"}
                ],
                "rows" => run_rows
              }
            }
          ]
        }

        socket
        |> assign(:rendered_components, Renderer.render_spec(detail_spec))
        |> assign(:detail, nil)
      else
        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to load flow"))
      end

    {:noreply, socket}
  end

  def handle_event("view_flow", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_flow", %{"id" => flow_id, "action" => action}, socket) do
    socket =
      case Api.toggle_flow(flow_id, action) do
        {:ok, _} ->
          push_toast(socket, :success, "Flow #{action}d")

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to #{action} flow"))
      end

    {:noreply, socket}
  end

  def handle_event("toggle_flow", _params, socket), do: {:noreply, socket}

  def handle_event("delete_flow", %{"id" => flow_id}, socket) do
    socket =
      case Api.delete_flow(flow_id) do
        {:ok, _} ->
          socket
          |> push_toast(:success, "Flow deleted")
          |> assign(:rendered_components, [])

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to delete flow"))
      end

    {:noreply, socket}
  end

  def handle_event("delete_flow", _params, socket), do: {:noreply, socket}

  # ── Commerce event log ────────────────────────────────────────────────────

  def handle_event("view_commerce_event", params, socket) do
    event_id = params["id"] || "—"
    topic = params["topic"] || "—"

    detail_spec = %{
      "components" => [
        %{
          "type" => "detail_card",
          "title" => "Event #{topic}",
          "data" => %{
            "fields" => [
              %{"label" => "Event ID", "value" => event_id},
              %{"label" => "Topic", "value" => topic},
              %{"label" => "Resource", "value" => params["resource_type"] || "—"},
              %{"label" => "Resource ID", "value" => params["resource_id"] || "—"},
              %{"label" => "Actor", "value" => params["actor"] || "—"}
            ]
          }
        }
      ]
    }

    {:noreply,
     socket
     |> assign(:rendered_components, Renderer.render_spec(detail_spec))
     |> assign(:detail, nil)}
  end

  # ── Audit log ─────────────────────────────────────────────────────────────

  def handle_event("view_audit_event", params, socket) do
    # Show audit event detail as a simple detail card rendered from params
    event_id = params["id"] || "—"
    event_data = params["data"] || "{}"

    detail_spec = %{
      "components" => [
        %{
          "type" => "detail_card",
          "title" => "Audit event #{event_id}",
          "data" => %{
            "fields" => [
              %{"label" => "Event ID", "value" => event_id},
              %{"label" => "Payload", "value" => event_data}
            ]
          }
        }
      ]
    }

    {:noreply,
     socket
     |> assign(:rendered_components, Renderer.render_spec(detail_spec))
     |> assign(:detail, nil)}
  end

  # ── Product drill-through from order line items ───────────────────────────

  def handle_event("view_product_from_order", %{"product_id" => product_id}, socket) do
    socket =
      case Api.get_product(product_id) do
        {:ok, product} ->
          assign(socket, :detail, %{type: :product, data: product})

        {:error, err} ->
          push_toast(
            socket,
            :error,
            api_error_message(err, "Product not found — it may have been deleted")
          )
      end

    {:noreply, socket}
  end

  def handle_event("view_product_from_order", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("edit_product", %{"id" => product_id}, socket) do
    case Api.get_product(product_id) do
      {:ok, product} ->
        # Build an edit form spec and show it as rendered components
        edit_spec = %{
          "components" => [
            %{
              "type" => "dynamic_form",
              "title" => "Edit product",
              "data" => %{
                "fields" => [
                  %{"key" => "title", "label" => "Title", "type" => "text", "required" => true},
                  %{
                    "key" => "description_html",
                    "label" => "Description",
                    "type" => "textarea"
                  },
                  %{
                    "key" => "status",
                    "label" => "Status",
                    "type" => "select",
                    "options" => ["draft", "active", "archived"]
                  },
                  %{"key" => "vendor", "label" => "Vendor", "type" => "text"},
                  %{"key" => "product_type", "label" => "Product type", "type" => "text"}
                ],
                "values" => product,
                "submit_event" => "update_product",
                "api_endpoint" => "_product_id"
              }
            },
            %{
              "type" => "dynamic_form",
              "title" => nil,
              "data" => %{
                "fields" => [
                  %{"key" => "_product_id", "label" => "Product ID", "type" => "hidden"}
                ],
                "values" => %{"_product_id" => product_id},
                "submit_event" => "update_product"
              }
            }
          ]
        }

        {:noreply,
         socket
         |> assign(:rendered_components, Renderer.render_spec(edit_spec))
         |> assign(:detail, nil)}

      {:error, err} ->
        {:noreply, push_toast(socket, :error, api_error_message(err, "Failed to load product"))}
    end
  end

  @impl true
  def handle_event("duplicate_product", %{"id" => product_id}, socket) do
    socket =
      case Api.get_product(product_id) do
        {:ok, product} ->
          clone =
            product
            |> Map.drop(["id", "created_at", "updated_at"])
            |> Map.put("title", "#{product["title"]} (copy)")

          case Api.create_product(clone) do
            {:ok, new_product} ->
              socket
              |> push_toast(:success, "Product duplicated successfully")
              |> assign(:detail, %{type: :product, data: new_product})

            {:error, err} ->
              push_toast(socket, :error, api_error_message(err, "Failed to duplicate product"))
          end

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to fetch product"))
      end

    {:noreply, socket}
  end

  def handle_event("duplicate_product", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("archive_product", %{"id" => product_id}, socket) do
    socket =
      case Api.archive_product(product_id) do
        {:ok, _} ->
          socket
          |> push_toast(:success, "Product archived")
          |> assign(:detail, nil)
          |> reload_tab_spec()

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to archive product"))
      end

    {:noreply, socket}
  end

  def handle_event("archive_product", _params, socket), do: {:noreply, socket}

  # ── Drill-through: Customers ───────────────────────────────────────────────

  @impl true
  def handle_event("view_customer", %{"id" => customer_id}, socket) do
    case Api.get("/v1/crm/customers/#{customer_id}") do
      {:ok, customer} -> {:noreply, assign(socket, :detail, %{type: :customer, data: customer})}
      _ -> {:noreply, socket}
    end
  end

  # ── Order actions ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("fulfill_order", %{"id" => order_id}, socket) do
    socket =
      case Api.create_fulfillment(order_id, %{}) do
        {:ok, _} ->
          socket_with_toast = push_toast(socket, :success, "Order marked as fulfilled")

          case Api.get_order(order_id) do
            {:ok, order} -> assign(socket_with_toast, :detail, %{type: :order, data: order})
            _ -> socket_with_toast
          end

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to fulfill order"))
      end

    {:noreply, socket}
  end

  def handle_event("fulfill_order", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("refund_order", %{"id" => order_id}, socket) do
    socket =
      case Api.create_refund(order_id, %{reason: "requested_by_customer"}) do
        {:ok, _} ->
          socket_with_toast = push_toast(socket, :success, "Refund issued successfully")

          case Api.get_order(order_id) do
            {:ok, order} -> assign(socket_with_toast, :detail, %{type: :order, data: order})
            _ -> socket_with_toast
          end

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to issue refund"))
      end

    {:noreply, socket}
  end

  def handle_event("refund_order", _params, socket), do: {:noreply, socket}

  # ── Inventory ─────────────────────────────────────────────────────────────

  @impl true
  def handle_event("restock_item", %{"id" => variant_id}, socket) do
    # Default restock: adjust by +10. Could be made configurable via a form.
    socket =
      case Api.adjust_inventory(%{
             variant_id: variant_id,
             location_id: "default",
             adjustment: 10
           }) do
        {:ok, _} ->
          socket
          |> push_toast(:success, "Inventory restocked (+10 units)")
          |> reload_tab_spec()

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to restock inventory"))
      end

    {:noreply, socket}
  end

  def handle_event("restock_item", _params, socket), do: {:noreply, socket}

  # ── Delete actions ─────────────────────────────────────────────────────────

  def handle_event("delete_product", %{"id" => product_id}, socket) do
    socket =
      case Api.delete_product(product_id) do
        {:ok, _} ->
          socket
          |> push_toast(:success, "Product deleted successfully")
          |> assign(:detail, nil)
          |> reload_tab_spec()

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to delete product"))
      end

    {:noreply, socket}
  end

  def handle_event("delete_product", _params, socket), do: {:noreply, socket}

  def handle_event("delete_customer", %{"id" => customer_id}, socket) do
    socket =
      case Api.delete_customer(customer_id) do
        {:ok, _} ->
          socket
          |> push_toast(:success, "Customer deleted successfully")
          |> assign(:detail, nil)
          |> reload_tab_spec()

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Failed to delete customer"))
      end

    {:noreply, socket}
  end

  def handle_event("delete_customer", _params, socket), do: {:noreply, socket}

  # ── Edit customer ──────────────────────────────────────────────────────────

  def handle_event("edit_customer", %{"id" => customer_id}, socket) do
    socket =
      case Api.get_customer(customer_id) do
        {:ok, customer} ->
          edit_spec = %{
            "components" => [
              %{
                "type" => "dynamic_form",
                "title" => "Edit customer",
                "data" => %{
                  "fields" => [
                    %{"key" => "_customer_id", "label" => "Customer ID", "type" => "hidden"},
                    %{"key" => "first_name", "label" => "First name", "type" => "text"},
                    %{"key" => "last_name", "label" => "Last name", "type" => "text"},
                    %{
                      "key" => "email",
                      "label" => "Email",
                      "type" => "text",
                      "required" => true
                    },
                    %{"key" => "phone", "label" => "Phone", "type" => "text"},
                    %{
                      "key" => "accepts_marketing",
                      "label" => "Accepts marketing",
                      "type" => "select",
                      "options" => ["true", "false"]
                    },
                    %{"key" => "note", "label" => "Note", "type" => "textarea"}
                  ],
                  "values" => Map.put(customer, "_customer_id", customer_id),
                  "submit_event" => "update_customer"
                }
              }
            ]
          }

          socket
          |> assign(:rendered_components, Renderer.render_spec(edit_spec))
          |> assign(:detail, nil)

        {:error, err} ->
          push_toast(socket, :error, api_error_message(err, "Could not load customer"))
      end

    {:noreply, socket}
  end

  def handle_event("edit_customer", _params, socket), do: {:noreply, socket}

  def handle_event("update_customer", params, socket) do
    customer_id = Map.get(params, "_customer_id", "")
    attrs = clean_form_params(Map.drop(params, ["_customer_id"]))

    socket =
      if customer_id == "" do
        push_toast(socket, :error, "Customer ID missing")
      else
        case Api.update_customer(customer_id, attrs) do
          {:ok, customer} ->
            socket
            |> push_toast(:success, "Customer updated")
            |> assign(:detail, %{type: :customer, data: customer})
            |> assign(:rendered_components, [])

          {:error, err} ->
            push_toast(socket, :error, api_error_message(err, "Failed to update customer"))
        end
      end

    {:noreply, socket}
  end

  def handle_event("add_customer_tag", params, socket) do
    customer_id = Map.get(params, "_customer_id", "")
    tag = Map.get(params, "tag", "")

    socket =
      cond do
        customer_id == "" ->
          push_toast(socket, :error, "Customer ID missing")

        tag == "" ->
          push_toast(socket, :error, "Tag cannot be empty")

        true ->
          case Api.add_customer_tag(customer_id, tag) do
            {:ok, _} ->
              push_toast(socket, :success, "Tag added")

            {:error, err} ->
              push_toast(socket, :error, api_error_message(err, "Failed to add tag"))
          end
      end

    {:noreply, socket}
  end

  # ── Keyboard shortcuts ──────────────────────────────────────────────────

  @impl true
  def handle_event("navigate_to", %{"tab" => tab_id}, socket) do
    tabs = TabStore.list()

    if Enum.any?(tabs, &(&1.id == tab_id)) do
      spec = TabStore.get_or_build_spec(tab_id)

      socket =
        socket
        |> assign(:active_tab_id, tab_id)
        |> assign(:tabs, tabs)
        |> assign(:detail, nil)
        |> assign(:rendered_components, Renderer.render_spec(spec))

      route = tab_id_to_route(tab_id)
      socket = if route, do: push_patch(socket, to: route), else: socket
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_shortcuts_modal", _, socket) do
    {:noreply, assign(socket, :shortcuts_modal, !socket.assigns.shortcuts_modal)}
  end

  @impl true
  def handle_event("close_shortcuts_modal", _, socket) do
    {:noreply, assign(socket, :shortcuts_modal, false)}
  end

  @impl true
  def handle_event("keyboard_escape", _, socket) do
    socket =
      cond do
        socket.assigns.shortcuts_modal ->
          assign(socket, :shortcuts_modal, false)

        socket.assigns.chat_open ->
          assign(socket, :chat_open, false)

        socket.assigns.detail != nil ->
          assign(socket, :detail, nil)

        true ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("keyboard_refresh", _, socket) do
    {:noreply, reload_tab_spec(socket)}
  end

  @impl true
  def handle_event("keyboard_new", _, socket) do
    tab_id = socket.assigns.active_tab_id

    creatable_tabs = ~w(products customers orders promotions shipping)

    if tab_id in creatable_tabs do
      {:noreply, assign(socket, :detail, %{type: :create_form, resource: tab_id})}
    else
      {:noreply, socket}
    end
  end

  # ── Clear detail panel ────────────────────────────────────────────────────

  @impl true
  def handle_event("clear_detail", _, socket) do
    {:noreply, assign(socket, :detail, nil)}
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Toast helpers
  # ──────────────────────────────────────────────────────────────────────────

  @toast_timeout 5_000

  defp push_toast(socket, kind, message) do
    id = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    toast = %{id: id, kind: kind, message: message}
    Process.send_after(self(), {:dismiss_toast, id}, @toast_timeout)
    update(socket, :toasts, fn toasts -> toasts ++ [toast] end)
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Form submission helpers
  # ──────────────────────────────────────────────────────────────────────────

  defp clean_form_params(params) do
    params
    |> Map.drop(["_csrf_token", "_api_endpoint"])
    |> Map.reject(fn {_k, v} -> v == "" end)
  end

  defp api_error_message(%{body: %{"error" => %{"message" => msg}}}, _default)
       when is_binary(msg),
       do: msg

  defp api_error_message(_err, default), do: default

  defp clear_rendered(socket) do
    assign(socket, :rendered_components, [])
  end

  # Build a create form spec for a given resource type
  # ── Detail spec builders (extracted to JargaAdmin.DetailSpecBuilder) ────────
  #
  # These functions have been moved to lib/jarga_admin/detail_spec_builder.ex
  # and are called via JargaAdmin.DetailSpecBuilder.build_*_spec/2.

  # (See also the remaining defp build_* functions below)

  # ── Sort helpers ──────────────────────────────────────────────────────────

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc

  # Walk the rendered components and sort rows in any data_table components
  defp apply_sort(components, sort_key, sort_dir) do
    Enum.map(components, fn comp ->
      case comp do
        %{type: :data_table, assigns: assigns} ->
          sorted_rows = sort_rows(assigns.rows, sort_key, sort_dir)

          %{
            comp
            | assigns: %{assigns | rows: sorted_rows, sort_key: sort_key, sort_dir: sort_dir}
          }

        other ->
          other
      end
    end)
  end

  defp sort_rows(rows, nil, _dir), do: rows

  defp sort_rows(rows, key, dir) do
    sorted =
      Enum.sort_by(rows, fn row ->
        # Rows are maps with string or atom keys — try both
        val = row[key] || row[String.to_atom(key)] || ""
        normalize_sort_val(val)
      end)

    if dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  defp normalize_sort_val(v) when is_binary(v), do: String.downcase(v)
  defp normalize_sort_val(v) when is_number(v), do: v
  defp normalize_sort_val(nil), do: ""
  defp normalize_sort_val(v), do: inspect(v)

  defp create_form_spec("product") do
    %{
      "components" => [
        %{
          "type" => "dynamic_form",
          "title" => "Add product",
          "data" => %{
            "fields" => [
              %{"key" => "title", "label" => "Title", "type" => "text", "required" => true},
              %{"key" => "description_html", "label" => "Description", "type" => "textarea"},
              %{
                "key" => "status",
                "label" => "Status",
                "type" => "select",
                "options" => ["draft", "active"]
              },
              %{"key" => "vendor", "label" => "Vendor", "type" => "text"},
              %{"key" => "product_type", "label" => "Product type", "type" => "text"},
              %{"key" => "tags", "label" => "Tags (comma-separated)", "type" => "text"}
            ],
            "submit_event" => "create_product"
          }
        }
      ]
    }
  end

  defp create_form_spec("customer") do
    %{
      "components" => [
        %{
          "type" => "dynamic_form",
          "title" => "Add customer",
          "data" => %{
            "fields" => [
              %{"key" => "first_name", "label" => "First name", "type" => "text"},
              %{"key" => "last_name", "label" => "Last name", "type" => "text"},
              %{
                "key" => "email",
                "label" => "Email",
                "type" => "text",
                "required" => true,
                "placeholder" => "customer@example.com"
              },
              %{"key" => "phone", "label" => "Phone", "type" => "text"},
              %{
                "key" => "accepts_marketing",
                "label" => "Accepts marketing",
                "type" => "select",
                "options" => ["true", "false"]
              }
            ],
            "submit_event" => "create_customer"
          }
        }
      ]
    }
  end

  defp create_form_spec("promotion") do
    %{
      "components" => [
        %{
          "type" => "dynamic_form",
          "title" => "Create discount",
          "data" => %{
            "fields" => [
              %{"key" => "name", "label" => "Name", "type" => "text", "required" => true},
              %{
                "key" => "discount_type",
                "label" => "Type",
                "type" => "select",
                "options" => ["percentage", "fixed_amount", "free_shipping"]
              },
              %{
                "key" => "discount_value",
                "label" => "Value (e.g. 10 for 10%)",
                "type" => "number"
              },
              %{"key" => "starts_at", "label" => "Start date", "type" => "text"},
              %{"key" => "ends_at", "label" => "End date", "type" => "text"},
              %{"key" => "min_purchase", "label" => "Minimum purchase", "type" => "number"}
            ],
            "submit_event" => "create_promotion"
          }
        }
      ]
    }
  end

  defp create_form_spec("shipping_zone") do
    %{
      "components" => [
        %{
          "type" => "dynamic_form",
          "title" => "Add shipping zone",
          "data" => %{
            "fields" => [
              %{"key" => "name", "label" => "Zone name", "type" => "text", "required" => true},
              %{
                "key" => "countries",
                "label" => "Countries (comma-separated ISO codes)",
                "type" => "text"
              },
              %{
                "key" => "active",
                "label" => "Active",
                "type" => "select",
                "options" => ["true", "false"]
              }
            ],
            "submit_event" => "create_shipping_zone"
          }
        }
      ]
    }
  end

  defp create_form_spec(_), do: %{"components" => []}

  defp reload_tab_spec(socket) do
    tab_id = socket.assigns.active_tab_id
    reload_tab_spec_for(socket, tab_id)
  end

  defp reload_tab_spec_for(socket, tab_id) do
    page = Map.get(socket.assigns.page_state, tab_id, 1)
    sort = Map.get(socket.assigns.sort_state, tab_id, %{key: nil, dir: :asc})
    filters = Map.get(socket.assigns.filter_state, tab_id, %{})

    TabStore.invalidate_spec(tab_id)

    # Build with params if any customisation is active
    spec =
      if page > 1 or map_size(filters) > 0 do
        TabSpecBuilder.build_spec(tab_id, page: page, filters: filters)
      else
        TabStore.get_or_build_spec(tab_id)
      end

    components =
      spec
      |> Renderer.render_spec()
      |> apply_sort(sort.key, sort.dir)

    assign(socket, :rendered_components, components)
  end

  # ──────────────────────────────────────────────────────────────────────────
  # PubSub / Info handlers
  # ──────────────────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:dismiss_toast, id}, socket) do
    {:noreply, update(socket, :toasts, fn toasts -> Enum.reject(toasts, &(&1.id == id)) end)}
  end

  # Task result from async tab spec build (triggered in switch_tab)
  def handle_info({ref, {tab_id, spec}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    socket =
      socket
      |> update(:loading_tabs, &MapSet.delete(&1, tab_id))

    socket =
      if socket.assigns.active_tab_id == tab_id do
        assign(socket, :rendered_components, Renderer.render_spec(spec))
      else
        socket
      end

    {:noreply, socket}
  end

  # Task DOWN — build crashed, clear loading state for the active tab
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    socket =
      socket
      |> update(:loading_tabs, &MapSet.delete(&1, socket.assigns.active_tab_id))

    {:noreply, socket}
  end

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
    tab = find_tab(socket.assigns.tabs, socket.assigns.active_tab_id)

    if tab && tab.refresh_interval != :off do
      # Force spec rebuild (clears ETS cache entry, re-fetches from API)
      TabStore.update(tab.id, %{ui_spec: nil})
      spec = TabStore.get_or_build_spec(tab.id)
      tabs = TabStore.list()

      {:noreply,
       socket |> assign(:tabs, tabs) |> assign(:rendered_components, Renderer.render_spec(spec))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:tab_refresh, tab_id}, socket) do
    # Re-schedule the next refresh (no-op in test env)
    case TabStore.get(tab_id) do
      {:ok, tab} when tab.refresh_interval != :off ->
        schedule_tab_refresh(tab_id, tab.refresh_interval)

      _ ->
        :ok
    end

    if socket.assigns.active_tab_id == tab_id and socket.assigns.detail == nil do
      # Only refresh the view when the tab is active and no detail panel is open
      socket =
        socket
        |> reload_tab_spec()
        |> update(:last_refreshed, &Map.put(&1, tab_id, DateTime.utc_now()))

      tabs = TabStore.list()
      {:noreply, assign(socket, :tabs, tabs)}
    else
      # Record the refresh timestamp even if not shown
      {:noreply, update(socket, :last_refreshed, &Map.put(&1, tab_id, DateTime.utc_now()))}
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Private helpers
  # ──────────────────────────────────────────────────────────────────────────

  defp find_tab(tabs, id) do
    Enum.find(tabs, &(&1.id == id))
  end

  @tab_routes %{
    "orders" => "/orders",
    "products" => "/products",
    "customers" => "/customers",
    "promotions" => "/promotions",
    "inventory" => "/inventory",
    "analytics" => "/analytics",
    "shipping" => "/shipping",
    "draft_orders" => "/draft-orders",
    "flows" => "/flows",
    "audit" => "/audit",
    "events" => "/events",
    "collections" => "/collections",
    "categories" => "/categories",
    "metaobjects" => "/metaobjects",
    "files" => "/files",
    "tax" => "/tax",
    "channels" => "/channels",
    "webhooks" => "/webhooks",
    "subscriptions" => "/subscriptions"
  }

  defp tab_id_to_route(tab_id), do: Map.get(@tab_routes, tab_id)

  # Returns pinned (non-default) tabs whose ui_spec has a matching nav_section
  defp saved_views_for(tabs, section) do
    default_ids =
      ~w(dashboard orders products customers promotions inventory analytics shipping draft_orders)

    Enum.filter(tabs, fn tab ->
      tab.id not in default_ids &&
        tab.pinnable &&
        tab.ui_spec != nil &&
        get_in(tab.ui_spec, ["nav_section"]) == section
    end)
  end

  defp current_tab_spec(_tabs, tab_id) do
    # Read from ETS — spec may already be cached from switch_tab or mount
    case TabStore.get(tab_id) do
      {:ok, %{ui_spec: spec}} -> spec
      _ -> nil
    end
  end

  defp schedule_auto_refresh do
    Process.send_after(self(), :auto_refresh, 30_000)
  end

  defp schedule_tab_refresh(tab_id, interval_secs) when is_integer(interval_secs) do
    unless Application.get_env(:jarga_admin, :disable_tab_refresh, false) do
      Process.send_after(self(), {:tab_refresh, tab_id}, interval_secs * 1000)
    end
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
