#!/usr/bin/env node

// Bundles both JS entries: the legacy LiveView app.js (until every page
// is ported) and the Elm SPA (js/spa.js -> src/Main.elm).

const esbuild = require("esbuild");
const ElmPlugin = require("esbuild-plugin-elm");

const args = process.argv.slice(2);
const watch = args.includes("--watch");
const deploy = args.includes("--deploy");

const plugins = [
  ElmPlugin({
    debug: false,
    optimize: deploy,
    pathToElm: "../node_modules/.bin/elm",
  }),
];

const config = {
  entryPoints: [
    { in: "js/app.js", out: "js/app" },
    { in: "js/spa.js", out: "js/spa" },
    { in: "js/echarts-loader.js", out: "js/echarts-loader" },
    { in: "js/sqlformatter-loader.js", out: "js/sqlformatter-loader" },
    { in: "css/app.css", out: "css/app" },
  ],
  bundle: true,
  target: "es2022",
  outdir: "../priv/static/assets",
  external: ["/fonts/*", "/images/*", "/favicon.svg"],
  // phoenix/phoenix_html/phoenix_live_view resolve from mix deps, same
  // as the old `mix esbuild` NODE_PATH setup.
  nodePaths: ["../deps"],
  plugins,
  logLevel: "info",
  minify: deploy,
  define: { "process.env.NODE_ENV": JSON.stringify(deploy ? "production" : "development") },
};

if (watch) {
  esbuild
    .context(config)
    .then((ctx) => {
      ctx.watch();
      console.log("Watching for changes...");
    })
    .catch(() => process.exit(1));
} else {
  esbuild.build(config).catch(() => process.exit(1));
}
