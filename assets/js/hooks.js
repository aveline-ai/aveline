import autosize from './autosize.min.js'

export const EnhancedTextarea = {
  mounted() {
    autosize(this.el)
    this.handleEvent("clear-value", () => {
      this.el.value = "";
      autosize.update(this.el);
      // TODO(Arie): Is there a more robust way to do this?
      setTimeout(() => {
        this.el.focus();
      }, 100);
    });
    // Event listener for Command+Enter to submit the form
    this.el.addEventListener("keydown", (event) => {
      if (event.key === "Enter" && event.metaKey) {
        this.el.form.dispatchEvent(new Event('submit', {bubbles: true, cancelable: true}));
      }
    });
  },
  destroyed() {
    autosize.destroy(this.el)
  }
};