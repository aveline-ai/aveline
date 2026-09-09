// Elm SPA entry. The server injects bootstrap data (csrf token, current
// user) as JSON in #spa-bootstrap; Elm owns everything after this file.

import { Elm } from "../src/Main.elm";
// fe-auth additions: clipboard copy + auth canvas backgrounds (see file).
import "./fe-auth.js";
// Sidebar collapse behavior for the workspace chrome (see file).
import "./chrome.js";

// ===== fe-doc-show custom elements ======================================
// Registered by the doc-show page agent. Elm renders these tags with
// data in attributes; each element owns its own children/behavior so
// the virtual DOM never fights third-party libs (ECharts, Prism).

// Fetch the (large) ECharts chunk once, only when a page actually
// contains a chart block — same laziness as assets/js/app.js.
let echartsLoading = null;
function loadECharts() {
  if (window.echarts) return Promise.resolve();
  if (!echartsLoading) {
    echartsLoading = new Promise((resolve, reject) => {
      const s = document.createElement("script");
      s.src = "/assets/js/echarts-loader.js";
      s.onload = resolve;
      s.onerror = reject;
      document.head.appendChild(s);
    });
  }
  return echartsLoading;
}

let sqlFormatterLoading = null;
function loadSqlFormatter() {
  if (window.sqlFormatter) return Promise.resolve();
  if (!sqlFormatterLoading) {
    sqlFormatterLoading = new Promise((resolve, reject) => {
      const s = document.createElement("script");
      s.src = "/assets/js/sqlformatter-loader.js";
      s.onload = resolve;
      s.onerror = reject;
      document.head.appendChild(s);
    });
  }
  return sqlFormatterLoading;
}

// Prism is loaded globally by the LiveView root layout; the SPA layout
// doesn't carry it, so load the same CDN build lazily on first use.
let prismLoading = null;
function loadPrism() {
  if (window.Prism && window.Prism.highlightElement) return Promise.resolve();
  if (!prismLoading) {
    window.Prism = window.Prism || {};
    window.Prism.manual = true;
    const css = document.createElement("link");
    css.rel = "stylesheet";
    css.href =
      "https://cdn.jsdelivr.net/npm/prismjs@1.29.0/themes/prism-tomorrow.min.css";
    document.head.appendChild(css);
    const script = (src) =>
      new Promise((resolve, reject) => {
        const s = document.createElement("script");
        s.src = src;
        s.onload = resolve;
        s.onerror = reject;
        document.head.appendChild(s);
      });
    prismLoading = script(
      "https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/prism-core.min.js"
    ).then(() =>
      script(
        "https://cdn.jsdelivr.net/npm/prismjs@1.29.0/plugins/autoloader/prism-autoloader.min.js"
      )
    );
  }
  return prismLoading;
}

// <aveline-chart spec='{"columns":..,"rows":..,"viz":..,"milestones":..}'>
// Renders a chart block's result via ECharts. Same option-building as
// the LV `Chart` hook in assets/js/app.js; palette mirrors the app CSS
// variables. The element owns its children entirely.
class AvelineChart extends HTMLElement {
  static get observedAttributes() {
    return ["spec"];
  }

  connectedCallback() {
    this.style.display = "block";
    loadECharts().then(() => {
      if (!this.isConnected) return;
      this.render();
      this._onResize = () => this.chart && this.chart.resize();
      window.addEventListener("resize", this._onResize);
    });
  }

  attributeChangedCallback() {
    if (window.echarts && this.isConnected) this.render();
  }

  disconnectedCallback() {
    window.removeEventListener("resize", this._onResize);
    if (this.chart) {
      this.chart.dispose();
      this.chart = null;
    }
  }

  render() {
    const echarts = window.echarts;
    let spec;
    try {
      spec = JSON.parse(this.getAttribute("spec"));
    } catch (_) {
      return;
    }
    const css = getComputedStyle(document.documentElement);
    const color = (name, fallback) =>
      (css.getPropertyValue(name) || fallback).trim();
    const text = color("--text-secondary", "#9BA1AA");
    const muted = color("--text-muted", "#6B7280");
    const border = color("--border", "#2A2D33");
    const accent = color("--accent", "#3B82F6");

    const xi = spec.columns.indexOf(spec.viz.x);
    const xs = spec.rows.map((r) => r[xi]);

    // A date/timestamp x-axis gets a real TIME axis, not a category one.
    const isDate = (v) =>
      typeof v === "string" && /^\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2})?/.test(v);
    const present = xs.filter((v) => v !== null && v !== undefined);
    const temporal = present.length > 0 && present.every(isDate);

    // Normalize: line/bar are sugar for a one-series combo.
    const seriesSpecs =
      spec.viz.type === "combo"
        ? spec.viz.series
        : [{ y: spec.viz.y, type: spec.viz.type }];
    const useRightAxis = seriesSpecs.some((s) => s.axis === "right");
    const palette = [accent, color("--attn", "#E09150"), "#8B5CF6", "#22C55E"];

    const series = seriesSpecs.map((s) => {
      const yi = spec.columns.indexOf(s.y);
      const ys = spec.rows.map((r) => (temporal ? [r[xi], r[yi]] : r[yi]));
      const base = {
        name: s.y,
        data: ys,
        yAxisIndex: s.axis === "right" ? 1 : 0,
      };
      return s.type === "line"
        ? {
            ...base,
            type: "line",
            showSymbol: xs.length < 30,
            symbolSize: 6,
            lineStyle: { width: 2 },
            areaStyle: seriesSpecs.length === 1 ? { opacity: 0.08 } : undefined,
          }
        : {
            ...base,
            type: "bar",
            barMaxWidth: 42,
            itemStyle: { borderRadius: [3, 3, 0, 0] },
          };
    });

    // Timeline milestones inside the x-range render as labeled vertical
    // markers on the first series.
    const day = (v) => String(v).slice(0, 10);
    const inRange = (date) => {
      if (temporal) {
        const days = present.map(day);
        const min = days.reduce((a, b) => (a < b ? a : b));
        const max = days.reduce((a, b) => (a > b ? a : b));
        return date >= min && date <= max;
      }
      return xs.some((v) => v !== null && day(v) === date);
    };
    const marks = (spec.milestones || []).filter(
      (m) => m.date && inRange(m.date)
    );
    if (marks.length && series.length) {
      const attn = color("--attn", "#E09150");
      series[0].markLine = {
        symbol: "none",
        animation: false,
        silent: false,
        lineStyle: { color: attn, type: "dashed", width: 1, opacity: 0.6 },
        label: {
          show: true,
          position: "insideEndTop",
          color: attn,
          fontSize: 10,
          opacity: 0.9,
          formatter: (p) => p.name,
        },
        emphasis: { lineStyle: { opacity: 1 }, label: { opacity: 1 } },
        tooltip: {
          formatter: (p) =>
            `<strong>${p.name}</strong><br/>${p.data.milestoneDate}` +
            (p.data.description ? `<br/>${p.data.description}` : ""),
        },
        data: marks.map((m) => ({
          xAxis: temporal
            ? m.date
            : xs.find((v) => v !== null && day(v) === m.date),
          name: m.name,
          milestoneDate: m.date,
          description: m.description || null,
        })),
      };
    }

    const yAxisBase = {
      type: "value",
      axisLabel: { color: muted, fontSize: 10.5 },
      splitLine: { lineStyle: { color: border, type: "dashed" } },
    };

    const option = {
      animationDuration: 250,
      grid: {
        left: 8,
        right: 12,
        top: seriesSpecs.length > 1 ? 32 : 16,
        bottom: 8,
        containLabel: true,
      },
      color: palette,
      textStyle: { fontFamily: "inherit" },
      tooltip: {
        trigger: "axis",
        backgroundColor: color("--bg-card", "#17181C"),
        borderColor: border,
        textStyle: { color: text, fontSize: 12 },
      },
      xAxis: {
        type: temporal ? "time" : "category",
        data: temporal ? undefined : xs,
        axisLine: { lineStyle: { color: border } },
        axisTick: { show: false },
        axisLabel: { color: muted, fontSize: 10.5 },
      },
      yAxis: useRightAxis
        ? [yAxisBase, { ...yAxisBase, splitLine: { show: false } }]
        : [yAxisBase],
      legend:
        seriesSpecs.length > 1
          ? {
              top: 0,
              right: 0,
              textStyle: { color: muted, fontSize: 11 },
              icon: "circle",
            }
          : undefined,
      series: series,
    };

    if (!this.chart) this.chart = window.echarts.init(this);
    this.chart.setOption(option, { notMerge: true });
    void echarts;
  }
}

// <aveline-code lang="elixir" code="..."> — builds the same
// <pre class="blk-code"><code class="language-x"> markup the LV block
// renderer emits, then Prism-highlights it once Prism is loaded.
class AvelineCode extends HTMLElement {
  static get observedAttributes() {
    return ["code", "lang"];
  }

  connectedCallback() {
    this.style.display = "contents";
    this.render();
  }

  attributeChangedCallback() {
    if (this.isConnected) this.render();
  }

  render() {
    const lang = this.getAttribute("lang") || "";
    const codeText = this.getAttribute("code") || "";
    this.innerHTML = "";
    const pre = document.createElement("pre");
    pre.className = "blk-code";
    pre.dataset.lang = lang;
    const code = document.createElement("code");
    if (lang !== "") code.className = "language-" + lang;
    code.textContent = codeText;
    pre.appendChild(code);
    this.appendChild(pre);
    loadPrism()
      .then(() => {
        if (this.isConnected && window.Prism) {
          window.Prism.highlightElement(code);
        }
      })
      .catch(() => {});
  }
}

// <aveline-sql dialect="postgresql" code="..."> — a chart block's SQL
// pane: pretty-print via sql-formatter (display only), then Prism.
// Same treatment as the LV SqlPane hook; the raw SQL still shows if
// formatting fails.
class AvelineSql extends HTMLElement {
  static get observedAttributes() {
    return ["code", "dialect"];
  }

  connectedCallback() {
    this.style.display = "contents";
    this.render();
  }

  attributeChangedCallback() {
    if (this.isConnected) this.render();
  }

  render() {
    const raw = this.getAttribute("code") || "";
    this.innerHTML = "";
    const pre = document.createElement("pre");
    pre.className = "blk-code";
    pre.dataset.lang = "sql";
    const code = document.createElement("code");
    code.className = "language-sql";
    code.textContent = raw;
    pre.appendChild(code);
    this.appendChild(pre);
    loadSqlFormatter()
      .then(() => {
        if (!this.isConnected) return;
        code.textContent = window.sqlFormatter.format(raw, {
          language: this.getAttribute("dialect") || "sql",
          keywordCase: "upper",
        });
      })
      .catch(() => {})
      .then(() => loadPrism())
      .then(() => {
        if (this.isConnected && window.Prism) {
          window.Prism.highlightElement(code);
        }
      })
      .catch(() => {});
  }
}

// <aveline-copy-link data-block-id="b_x" class="block-anchor"> — the
// per-block ¶ anchor. Elm renders the icon child; this element only
// owns the click: copy the deep link, update the hash, smooth-scroll,
// flash the target — same behavior as the LV CopyBlockLink hook.
class AvelineCopyLink extends HTMLElement {
  connectedCallback() {
    if (this._bound) return;
    this._bound = true;
    this.addEventListener("click", async (e) => {
      e.preventDefault();
      const blockId = this.dataset.blockId;
      const base =
        window.location.origin +
        window.location.pathname +
        window.location.search;
      // No block id = title-level anchor: copy the doc URL itself.
      const url = blockId ? base + "#" + blockId : base;
      try {
        await navigator.clipboard.writeText(url);
      } catch (_) {}
      if (blockId) {
        history.replaceState(null, "", "#" + blockId);
        const target = document.getElementById(blockId);
        if (target) {
          target.scrollIntoView({ behavior: "smooth", block: "start" });
          target.classList.remove("blk-target-flash");
          void target.offsetWidth;
          target.classList.add("blk-target-flash");
        }
      }
      this.classList.add("copied");
      clearTimeout(this._t);
      this._t = setTimeout(() => this.classList.remove("copied"), 1200);
    });
  }
}

customElements.define("aveline-chart", AvelineChart);
customElements.define("aveline-code", AvelineCode);
customElements.define("aveline-sql", AvelineSql);
customElements.define("aveline-copy-link", AvelineCopyLink);

// If the page loaded with a #block hash, scroll + flash it once Elm has
// rendered the block (same behavior as the LV flashCurrentHash). Elm
// renders asynchronously after data loads, so poll briefly.
function flashCurrentHash() {
  const id = window.location.hash.slice(1);
  if (!id) return;
  let tries = 0;
  const attempt = () => {
    const el = document.getElementById(id);
    if (!el) {
      if (tries++ < 40) setTimeout(attempt, 250);
      return;
    }
    el.scrollIntoView({ behavior: "smooth", block: "start" });
    el.classList.remove("blk-target-flash");
    void el.offsetWidth;
    el.classList.add("blk-target-flash");
  };
  attempt();
}
window.addEventListener("load", () => setTimeout(flashCurrentHash, 80));
window.addEventListener("hashchange", flashCurrentHash);

// ===== end fe-doc-show custom elements ==================================

const bootstrap = JSON.parse(
  document.getElementById("spa-bootstrap").textContent
);

Elm.Main.init({
  node: document.getElementById("elm-root"),
  flags: bootstrap,
});
