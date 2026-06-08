export default {
  mounted() {
    let closeDueToAction = false;
    const modal = this.el;

    setTimeout(() => {
      modal.showModal();
    }, 50);

    modal.addEventListener("close", (event) => {
      // Prevent closing if modal is not closeable
      if (!modal.dataset.closeable) {
        event.preventDefault();
        modal.showModal();
        return;
      }

      // Handles the dialog's native close event.
      // Triggered when the user clicks outside the modal or presses ESC.
      setTimeout(() => {
        if (closeDueToAction) return;
        liveSocket.execJS(modal, modal.dataset.cancel);
        closeDueToAction = false;
      }, 300);
    });

    modal.addEventListener("close-dialog", (event) => {
      // Avoid running cancel action when closing via LiveView
      closeDueToAction = true;
      modal.close();
    });
  },
};
