import autosize from './autosize.min.js'

export const ClearableAutosizingTextarea = {
  mounted() {
    autosize(this.el)
    this.handleEvent("clear-value", () => {
      this.el.value = "";
      autosize.update(this.el);
      // TODO(Arie): Is there a more robust way to do this?
      setTimeout(() => {
        this.el.focus();
      }, 100);
    })
    this.handleEvent("set-value", (event) => {
      this.el.value = event.value;
      autosize.update(this.el);
      setTimeout(() => {
        this.el.focus();
      }, 100);
    })
  },
  destroyed() {
    autosize.destroy(this.el)
  }
};