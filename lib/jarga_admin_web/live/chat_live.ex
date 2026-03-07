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

  alias JargaAdmin.{UiSpec, Renderer, TabStore, Api}
  alias JargaAdmin.Quecto.Bridge
  alias Phoenix.{PubSub, LiveView.JS}

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

    {:ok, socket}
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Render
  # ──────────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Flash / toast notifications --%>
    <div
      :if={@flash["info"]}
      id="flash-info"
      role="alert"
      class="fixed top-4 right-4 z-50 flex items-center gap-3 rounded-lg bg-green-600 px-5 py-3 text-white shadow-lg"
      phx-click={JS.hide(to: "#flash-info")}
    >
      <.icon name="hero-check-circle" class="w-5 h-5" />
      <span>{@flash["info"]}</span>
    </div>

    <div
      :if={@flash["error"]}
      id="flash-error"
      role="alert"
      class="fixed top-4 right-4 z-50 flex items-center gap-3 rounded-lg bg-red-600 px-5 py-3 text-white shadow-lg"
      phx-click={JS.hide(to: "#flash-error")}
    >
      <.icon name="hero-x-circle" class="w-5 h-5" />
      <span>{@flash["error"]}</span>
    </div>

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
          </div>

          <div :if={@active_tab_id == "activity"}>
            <JargaAdminWeb.JargaComponents.activity_feed events={@activity_events} />
          </div>

          <div :if={@active_tab_id != "activity"}>
            <div :if={current_tab_spec(@tabs, @active_tab_id) == nil} class="j-empty-state">
              <p class="j-empty-heading">Loading…</p>
            </div>
            <div :if={current_tab_spec(@tabs, @active_tab_id) != nil}>
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
    # Build spec lazily — fetches from API on first access, cached in ETS thereafter
    spec = TabStore.get_or_build_spec(tab_id)
    tabs = TabStore.list()
    tab = find_tab(tabs, tab_id)
    components = Renderer.render_spec(spec)

    # Schedule refresh if tab has an interval
    if tab && tab.refresh_interval != :off do
      schedule_tab_refresh(tab_id, tab.refresh_interval)
    end

    {:noreply,
     socket
     |> assign(:active_tab_id, tab_id)
     |> assign(:tabs, tabs)
     |> assign(:rendered_components, components)
     |> assign(:context_menu, nil)
     |> assign(:detail, nil)
     |> assign(:menu_open, false)}
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
    # Generic fallback — route via hidden _api_endpoint field if present
    clean = clean_form_params(params)

    socket =
      case Map.get(params, "_api_endpoint") do
        nil ->
          socket
          |> put_flash(:error, "Form has no API endpoint configured")

        endpoint ->
          case Api.post(endpoint, clean) do
            {:ok, _} -> socket |> put_flash(:info, "Saved successfully") |> clear_rendered()
            {:error, _} -> socket |> put_flash(:error, "Failed to save. Please try again.")
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
          |> put_flash(:info, "Product created successfully")
          |> clear_rendered()
          |> reload_tab_spec()

        {:error, err} ->
          socket |> put_flash(:error, api_error_message(err, "Failed to create product"))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_customer", params, socket) do
    socket =
      case Api.create_customer(clean_form_params(params)) do
        {:ok, _} ->
          socket
          |> put_flash(:info, "Customer created successfully")
          |> clear_rendered()
          |> reload_tab_spec()

        {:error, err} ->
          socket |> put_flash(:error, api_error_message(err, "Failed to create customer"))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_order", params, socket) do
    socket =
      case Api.post("/v1/oms/orders", clean_form_params(params)) do
        {:ok, _} ->
          socket
          |> put_flash(:info, "Order created successfully")
          |> clear_rendered()
          |> reload_tab_spec()

        {:error, err} ->
          socket |> put_flash(:error, api_error_message(err, "Failed to create order"))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_promotion", params, socket) do
    socket =
      case Api.create_promotion(clean_form_params(params)) do
        {:ok, _} ->
          socket
          |> put_flash(:info, "Promotion created successfully")
          |> clear_rendered()
          |> reload_tab_spec()

        {:error, err} ->
          socket |> put_flash(:error, api_error_message(err, "Failed to create promotion"))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_shipping_zone", params, socket) do
    socket =
      case Api.create_shipping_zone(clean_form_params(params)) do
        {:ok, _} ->
          socket
          |> put_flash(:info, "Shipping zone created successfully")
          |> clear_rendered()
          |> reload_tab_spec()

        {:error, err} ->
          socket |> put_flash(:error, api_error_message(err, "Failed to create shipping zone"))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_form", _, socket) do
    {:noreply, assign(socket, :rendered_components, [])}
  end

  def handle_event("retry_tab", _, socket) do
    {:noreply, reload_tab_spec(socket)}
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

  @impl true
  def handle_event("edit_product", %{"id" => product_id}, socket) do
    case Api.get_product(product_id) do
      {:ok, product} -> {:noreply, assign(socket, :detail, %{type: :product, data: product})}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("duplicate_product", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("archive_product", _params, socket) do
    {:noreply, socket}
  end

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
  def handle_event("fulfill_order", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("refund_order", _params, socket) do
    {:noreply, socket}
  end

  # ── Inventory ─────────────────────────────────────────────────────────────

  @impl true
  def handle_event("restock_item", _params, socket) do
    {:noreply, socket}
  end

  # ── Clear detail panel ────────────────────────────────────────────────────

  @impl true
  def handle_event("clear_detail", _, socket) do
    {:noreply, assign(socket, :detail, nil)}
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

  defp reload_tab_spec(socket) do
    tab_id = socket.assigns.active_tab_id

    TabStore.invalidate_spec(tab_id)
    spec = TabStore.get_or_build_spec(tab_id)
    assign(socket, :rendered_components, Renderer.render_spec(spec))
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
    if socket.assigns.active_tab_id == tab_id do
      # Force spec rebuild for this tab
      TabStore.update(tab_id, %{ui_spec: nil})
      spec = TabStore.get_or_build_spec(tab_id)
      tabs = TabStore.list()

      {:noreply,
       socket |> assign(:tabs, tabs) |> assign(:rendered_components, Renderer.render_spec(spec))}
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
