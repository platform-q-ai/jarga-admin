/**
 * Jarga Storefront — LiveView Hooks
 *
 * Scroll-hide navigation, image hover swap, lazy loading,
 * and cart drawer interactions.
 */

/**
 * StorefrontNav — scroll-triggered nav visibility.
 * Hides nav on scroll-down, shows on scroll-up.
 */
export const StorefrontNav = {
  mounted() {
    this.lastScrollY = window.scrollY
    this.ticking = false

    this._onScroll = () => {
      if (!this.ticking) {
        window.requestAnimationFrame(() => {
          const currentY = window.scrollY
          if (currentY > this.lastScrollY && currentY > 100) {
            this.el.classList.add("sf-nav-hidden")
          } else {
            this.el.classList.remove("sf-nav-hidden")
          }
          this.lastScrollY = currentY
          this.ticking = false
        })
        this.ticking = true
      }
    }

    window.addEventListener("scroll", this._onScroll, { passive: true })
  },
  destroyed() {
    window.removeEventListener("scroll", this._onScroll)
  }
}

/**
 * ImageHoverSwap — swaps product card images on hover.
 * Uses CSS opacity transitions for smooth effect.
 */
export const ImageHoverSwap = {
  mounted() {
    // CSS handles the hover swap via .sf-product-card-hover opacity
    // This hook preloads the hover image for instant swap
    const hoverImg = this.el.querySelector(".sf-product-card-hover")
    if (hoverImg) {
      const preload = new Image()
      preload.src = hoverImg.src
    }
  }
}

/**
 * FlushCardHeight — pixel-perfect flush spanning cards.
 *
 * Measures a standard 1-col card's image height in the same grid,
 * then sets --sf-card-img-h on all flush spanning cards so they
 * match exactly regardless of viewport width or grid gap.
 */
export const FlushCardHeight = {
  mounted() {
    this._sync = () => this._syncHeights()
    // Run after images load / layout settles
    requestAnimationFrame(() => {
      this._syncHeights()
      // Re-sync on resize
      this._ro = new ResizeObserver(() => this._syncHeights())
      this._ro.observe(this.el)
    })
  },
  updated() {
    requestAnimationFrame(() => this._syncHeights())
  },
  destroyed() {
    if (this._ro) this._ro.disconnect()
  },
  _syncHeights() {
    // Find a standard (non-spanning) card image wrap in this grid
    const stdWrap = this.el.querySelector(
      ".sf-product-card:not([class*=sf-card-span]) .sf-product-card-image-wrap"
    )
    if (!stdWrap) return

    const targetH = stdWrap.getBoundingClientRect().height
    if (targetH <= 0) return

    // Apply to all flush multi-image containers
    const flushImgs = this.el.querySelectorAll(
      ".sf-card-height-flush .sf-product-card-multi-image"
    )
    for (const el of flushImgs) {
      el.style.setProperty("--sf-card-img-h", targetH + "px")
    }
  }
}
