import autosize from 'autosize'

export const AutosizeTextarea = {
  mounted() {
    autosize(this.el)
  },
  destroyed() {
    autosize.destroy(this.el)
  }
};