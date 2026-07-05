// Separate esbuild entry point: the ECharts bundle, exposed as a
// global. Loaded on demand by the Chart hook the first time a chart
// block appears on a page — pages without charts never fetch it.
import * as echarts from "../vendor/echarts.esm.min.js"
window.echarts = echarts
