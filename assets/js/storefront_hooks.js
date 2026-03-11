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
