import autosize from './autosize.min.js'

export const AutosizeTextarea = {
  mounted() {
    autosize(this.el)
  },
};