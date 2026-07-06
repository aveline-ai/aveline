// Separate esbuild entry: sql-formatter (self-contained UMD build),
// exposed as a global. Loaded on demand the first time a chart's SQL
// tab is opened — pages that never show SQL never fetch it.
import * as sqlFormatter from "../vendor/sql-formatter.min.js"
window.sqlFormatter = sqlFormatter
