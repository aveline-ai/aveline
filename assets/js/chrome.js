// Sidebar collapse for the Elm SPA chrome (src/Ui/Chrome.elm).
//
// Ports of two pieces of the LiveView app:
//   - the pre-paint snippet in layouts/root.html.heex (apply the saved
//     collapsed state before Elm renders, falling back to viewport
//     width when the user has no preference), and
//   - the SidebarCollapse hook in js/app.js (toggle + persistence).
//
// Source of truth is `html.sidebar-collapsed` — a class on the document
// element, outside the Elm root, so Elm's virtual DOM never fights it
// and no ports are needed. The toggle button rendered by Ui.Chrome
// carries `data-sidebar-toggle`; we listen via delegation so it keeps
// working across Elm re-renders. If this file isn't imported the
// button is simply inert and the sidebar stays expanded.
//
// Wire-up (coordinator): add to assets/js/spa.js:
//   import "./chrome.js";

const root = document.documentElement;
const KEY = "aveline:sidebarCollapsed";

const setCollapsed = (val, persist) => {
  root.classList.toggle("sidebar-collapsed", val);
  if (persist) localStorage.setItem(KEY, val ? "1" : "0");
};

// Apply saved state at module evaluation — before Elm's first paint.
const pref = localStorage.getItem(KEY);
if (pref === "1") setCollapsed(true, false);
else if (pref === "0") setCollapsed(false, false);
else setCollapsed(window.innerWidth < 1024, false);

document.addEventListener("click", (e) => {
  const btn = e.target.closest && e.target.closest("[data-sidebar-toggle]");
  if (!btn) return;
  e.preventDefault();
  setCollapsed(!root.classList.contains("sidebar-collapsed"), true);
});

// When the user hasn't set a preference, follow the viewport so
// resizing across the breakpoint feels right.
window.addEventListener("resize", () => {
  if (localStorage.getItem(KEY) === null) {
    setCollapsed(window.innerWidth < 1024, false);
  }
});
