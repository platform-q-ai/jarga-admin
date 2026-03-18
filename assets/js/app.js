// Jarga Admin — Phoenix LiveView app entry point

import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"

import { StorefrontNav, ImageHoverSwap, FlushCardHeight } from "./storefront_hooks"

// ── LiveView Hooks ───────────────────────────────────────────────────────────

const Hooks = {}

// Storefront hooks
Hooks.StorefrontNav = StorefrontNav
Hooks.ImageHoverSwap = ImageHoverSwap
Hooks.FlushCardHeight = FlushCardHeight

/**
 * AutoScroll — keeps the chat pane scrolled to the bottom unless the
 * user has manually scrolled up.
 */
Hooks.AutoScroll = {
  mounted() {
    this.pauseScroll = false
    this.el.addEventListener("scroll", () => {
      const { scrollTop, scrollHeight, clientHeight } = this.el
      // If user scrolled up more than 100px from bottom, pause auto-scroll
      this.pauseScroll = scrollHeight - scrollTop - clientHeight > 100
    })
    this.scrollToBottom()
  },
  updated() {
    if (!this.pauseScroll) {
      this.scrollToBottom()
    }
  },
  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
  }
}

/**
 * TextareaEnter — submit the chat form on Enter (without Shift).
 */
Hooks.TextareaEnter = {
  mounted() {
    this.el.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault()
        const form = this.el.closest("form")
        if (form) {
          form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
        }
      }
    })
  }
}

/**
 * SortableTabs — drag-to-reorder tabs using native HTML5 drag API.
 * Pushes "reorder_tabs" event to the LiveView with new id order.
 */
Hooks.SortableTabs = {
  mounted() {
    this.setupDrag()
  },
  updated() {
    this.setupDrag()
  },
  setupDrag() {
    const tabs = Array.from(this.el.querySelectorAll("[data-tab-id]"))
    tabs.forEach(tab => {
      tab.setAttribute("draggable", "true")

      tab.addEventListener("dragstart", (e) => {
        e.dataTransfer.effectAllowed = "move"
        e.dataTransfer.setData("text/plain", tab.dataset.tabId)
        tab.classList.add("j-tab-ghost")
      })

      tab.addEventListener("dragend", () => {
        tab.classList.remove("j-tab-ghost")
      })

      tab.addEventListener("dragover", (e) => {
        e.preventDefault()
        e.dataTransfer.dropEffect = "move"
      })

      tab.addEventListener("drop", (e) => {
        e.preventDefault()
        const draggedId = e.dataTransfer.getData("text/plain")
        const targetId = tab.dataset.tabId

        if (draggedId && targetId && draggedId !== targetId) {
          const allTabs = Array.from(this.el.querySelectorAll("[data-tab-id]"))
          const ids = allTabs.map(t => t.dataset.tabId)
          const fromIdx = ids.indexOf(draggedId)
          const toIdx = ids.indexOf(targetId)

          if (fromIdx !== -1 && toIdx !== -1) {
            ids.splice(fromIdx, 1)
            ids.splice(toIdx, 0, draggedId)
            this.pushEvent("reorder_tabs", { ids })
          }
        }
      })
    })
  }
}

/**
 * Chart — renders a Chart.js chart from data-chart JSON attribute.
 * Re-renders on LiveView update if data changes.
 */
Hooks.Chart = {
  mounted() {
    this.renderChart()
  },
  updated() {
    const newData = this.el.dataset.chart
    if (newData !== this.lastData) {
      this.destroyChart()
      this.renderChart()
    }
  },
  destroyed() {
    this.destroyChart()
  },
  renderChart() {
    this.lastData = this.el.dataset.chart
    if (!this.lastData) return

    let config
    try {
      config = JSON.parse(this.lastData)
    } catch (e) {
      console.error("Chart: invalid JSON", e)
      return
    }

    // Dynamically import Chart.js (loaded via npm or CDN)
    if (typeof window.Chart !== "undefined") {
      this.chart = this.buildChart(window.Chart, config)
    } else {
      import("chart.js/auto").then(({ Chart }) => {
        window.Chart = Chart
        this.chart = this.buildChart(Chart, config)
      }).catch(() => {
        // Fallback: load from CDN
        if (!document.querySelector("#chartjs-cdn")) {
          const s = document.createElement("script")
          s.id = "chartjs-cdn"
          s.src = "https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js"
          s.onload = () => {
            this.chart = this.buildChart(window.Chart, config)
          }
          document.head.appendChild(s)
        }
      })
    }
  },
  buildChart(Chart, config) {
    const jargaColor = "#181512"
    const mutedColor = "#9a8e82"

    // Apply Jarga theme defaults
    const datasets = (config.datasets || []).map((ds, i) => ({
      ...ds,
      borderColor: i === 0 ? jargaColor : mutedColor,
      backgroundColor: config.type === "line"
        ? (i === 0 ? "rgba(24,21,18,0.06)" : "rgba(154,142,130,0.06)")
        : (i === 0 ? jargaColor : mutedColor),
      borderWidth: 2,
      pointRadius: 3,
      tension: 0.3,
      fill: config.type === "line"
    }))

    return new Chart(this.el, {
      type: config.type || "line",
      data: { labels: config.labels || [], datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: datasets.length > 1 },
          tooltip: {
            backgroundColor: jargaColor,
            titleColor: "#f7f6f3",
            bodyColor: "#f7f6f3",
            cornerRadius: 4,
            padding: 10
          }
        },
        scales: config.type !== "doughnut" ? {
          x: {
            grid: { color: "rgba(24,21,18,0.06)" },
            ticks: {
              color: mutedColor,
              font: { family: "Manrope, sans-serif", size: 11 }
            }
          },
          y: {
            grid: { color: "rgba(24,21,18,0.06)" },
            ticks: {
              color: mutedColor,
              font: { family: "Manrope, sans-serif", size: 11 }
            }
          }
        } : {}
      }
    })
  },
  destroyChart() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }
}

/**
 * KeyboardShortcuts — global keyboard shortcuts for navigation and actions.
 * Pushes server events: navigate_to, keyboard_refresh, keyboard_escape,
 * keyboard_new, toggle_shortcuts_modal.
 */
Hooks.KeyboardShortcuts = {
  mounted() {
    this._gPressed = false
    this._gTimer = null

    this._handler = (e) => {
      // Ignore when typing in inputs/textareas
      const tag = e.target.tagName
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || e.target.isContentEditable) return

      // "G then X" navigation combos
      if (this._gPressed) {
        this._gPressed = false
        clearTimeout(this._gTimer)
        const map = { o: "orders", p: "products", c: "customers", a: "analytics", i: "inventory", s: "shipping", m: "promotions" }
        const tab = map[e.key.toLowerCase()]
        if (tab) {
          e.preventDefault()
          this.pushEvent("navigate_to", { tab })
        }
        return
      }

      if (e.key === "g") {
        this._gPressed = true
        this._gTimer = setTimeout(() => { this._gPressed = false }, 500)
        return
      }

      if (e.key === "?" || (e.key === "/" && e.shiftKey)) {
        e.preventDefault()
        this.pushEvent("toggle_shortcuts_modal", {})
      } else if (e.key === "Escape") {
        // Only push if a modal, chat, or detail panel might be open
        const hasModal = document.getElementById("keyboard-shortcuts-modal")
        const chatOpen = document.querySelector(".j-chat-popover.open")
        if (hasModal || chatOpen) {
          this.pushEvent("keyboard_escape", {})
        }
      } else if (e.key === "r" && !e.ctrlKey && !e.metaKey) {
        e.preventDefault()
        this.pushEvent("keyboard_refresh", {})
      } else if (e.key === "n" && !e.ctrlKey && !e.metaKey) {
        e.preventDefault()
        this.pushEvent("keyboard_new", {})
      }
    }

    window.addEventListener("keydown", this._handler)
  },
  destroyed() {
    window.removeEventListener("keydown", this._handler)
    clearTimeout(this._gTimer)
  }
}

/**
 * ContextMenu — show/hide tab context menu at cursor position.
 */
Hooks.ContextMenu = {
  mounted() {
    document.addEventListener("click", (e) => {
      if (!this.el.contains(e.target)) {
        this.pushEvent("close_context_menu", {})
      }
    })
  }
}

/**
 * ChatHover — mouseenter the FAB or panel area opens chat;
 * mouseleave starts a short delay then closes (cancels if re-entered).
 */
Hooks.ChatHover = {
  mounted() {
    this._closeTimer = null

    this.el.addEventListener("mouseenter", () => {
      clearTimeout(this._closeTimer)
      this.pushEvent("open_chat", {})
    })

    this.el.addEventListener("mouseleave", () => {
      // Give user 600ms grace to move back; if they leave entirely, close.
      this._closeTimer = setTimeout(() => {
        this.pushEvent("close_chat", {})
      }, 600)
    })
  },
  destroyed() {
    clearTimeout(this._closeTimer)
  }
}

// ── LiveSocket setup ─────────────────────────────────────────────────────────

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks
})

// Progress bar
topbar.config({ barColors: { 0: "#181512" }, shadowColor: "rgba(0,0,0,0.2)" })
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket

// ── Dev helpers ──────────────────────────────────────────────────────────────

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    reloader.enableServerLogs()

    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", () => keyDown = null)
    window.addEventListener("click", e => {
      if (keyDown === "c") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if (keyDown === "d") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
