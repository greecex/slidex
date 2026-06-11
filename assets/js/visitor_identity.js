// Colocated / imported hook for the /vote/:slug LiveView.
// Persists a stable opaque visitor ID in localStorage for guests so they can
// vote across reconnects/tabs and appear consistently in the participant list
// (used as seed for IdenticonSvg).
export default {
  mounted() {
    this.pushVisitorId();
  },
  reconnected() {
    this.pushVisitorId();
  },
  pushVisitorId() {
    let id = localStorage.getItem("slidex_visitor");
    if (!id) {
      if (typeof crypto !== "undefined" && crypto.randomUUID) {
        id = crypto.randomUUID();
      } else {
        id = "v-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 10);
      }
      localStorage.setItem("slidex_visitor", id);
    }
    this.pushEvent("visitor-identified", { visitor_id: id });
  },
};
