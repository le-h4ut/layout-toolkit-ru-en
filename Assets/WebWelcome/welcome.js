"use strict";
(() => {
  const bridge = window.chrome?.webview;
  const $ = id => document.getElementById(id);
  const send = (command, extra = {}) => bridge?.postMessage({command, ...extra});
  let ready = false;

  function render(state) {
    document.documentElement.dataset.theme = state.theme?.toLowerCase() === "dark" ? "dark" : "light";
    for (const [id, key] of Object.entries({
      "layout-full":"layoutFull", "layout-majority":"layoutMajority",
      "live-convert":"liveConvert", "live-toggle":"liveToggle",
      "unicode":"unicode", "caps-full":"capsFull", "caps-smart":"capsSmart"
    })) $(id).textContent = state[key] || "—";
    $("enable-live").checked = !!state.live;
    $("save").textContent = state.firstRun ? "Начать" : "Сохранить";
    ready = true;
  }

  bridge?.addEventListener("message", ({data}) => {
    if (data.type === "state") render(data.state);
  });
  $("save").addEventListener("click", () => { if (ready) send("save", {live: $("enable-live").checked}); });
  $("settings").addEventListener("click", () => send("settings"));
  $("close").addEventListener("click", () => send("close"));
  document.addEventListener("keydown", event => {
    if (event.key === "Escape") { event.preventDefault(); send("close"); }
  });
  send("ready");
})();
