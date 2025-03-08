import autosize from './autosize.min.js'

export const EnhancedTextarea = {
  mounted() {
    this.el.focus();
    autosize(this.el);
    // Event listener to disable textarea on form submission. Because we use phx-update="ignore", Phoenix doesn't
    // automatically disable the textarea when the form is submitted.
    this.el.form.addEventListener("submit", (event) => {
      const newMessage = this.el.value;
      const newMessageTrimmedLength = newMessage.trim().length;

      if (newMessageTrimmedLength === 0) {
        event.preventDefault();
        return false;
      }

      this.el.disabled = true;
      return true;
    });
    // Event listener for Command+Enter to submit the form. Purposefully done in JS to be snappy.
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