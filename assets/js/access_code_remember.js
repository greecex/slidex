export default {
  mounted() {
    this.slug = this.el.dataset.slug;
    if (!this.slug) return;

    const gate = document.getElementById("access-code-gate");
    const code = localStorage.getItem(this.storageKey(this.slug));

    if (code && gate) {
      gate.classList.add("hidden");
      this.pushEvent("access_code_remembered", { slug: this.slug, code });
    }
    // if no code, leave the gate visible (server rendered it for !granted)
  },

  reconnected() {
    // re-check on reconnect in case
    const gate = document.getElementById("access-code-gate");
    const code = localStorage.getItem(this.storageKey(this.slug));
    if (code && gate) {
      gate.classList.add("hidden");
      this.pushEvent("access_code_remembered", { slug: this.slug, code });
    }
  },

  handleEvent(event, payload) {
    const gate = document.getElementById("access-code-gate");
    if (event === "slidex:remember-access-code") {
      const { slug, code } = payload || {};
      if (slug === this.slug && code) {
        localStorage.setItem(this.storageKey(slug), code);
        if (gate) gate.classList.add("hidden");
      }
    } else if (event === "slidex:clear-access-code" || event === "slidex:show-access-gate") {
      if (gate) gate.classList.remove("hidden");
      if (event === "slidex:clear-access-code") {
        const { slug } = payload || {};
        if (slug === this.slug) {
          localStorage.removeItem(this.storageKey(slug));
        }
      }
    }
  },

  storageKey(slug) {
    return `slidex_access_code_${slug}`;
  },
};
