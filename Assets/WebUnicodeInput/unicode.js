"use strict";
(() => {
  const $ = selector => document.querySelector(selector);
  const bridge = window.chrome?.webview;
  const pending = new Map();
  let sequence = 0, state, previewSequence = 0, busy = false, selected = null, toastTimer;

  function request(command, data = {}) {
    return new Promise((resolve, reject) => {
      if (!bridge) return reject(new Error("Нет соединения с Layout Toolkit"));
      const id = ++sequence;
      const timer = setTimeout(() => { pending.delete(id); reject(new Error("Layout Toolkit не ответил")); }, 15000);
      pending.set(id, { resolve, reject, timer });
      bridge.postMessage({ id, command, data });
    });
  }

  bridge?.addEventListener("message", ({ data }) => {
    if (pending.has(data.id)) {
      const item = pending.get(data.id); pending.delete(data.id); clearTimeout(item.timer);
      data.ok ? item.resolve(data.result) : item.reject(new Error(data.error));
    } else if (data.type === "state") { state = data.state; render(false); }
    else if (data.type === "open") { state = data.state; render(true); }
    else if (data.type === "theme") applyTheme(data.theme);
    else if (data.type === "reset") resetComposer();
    else if (data.type === "focus") focusItem(data.kind, data.index);
    else if (data.type === "error") toast(data.message, true);
  });

  function escape(value) { return String(value ?? "").replace(/[&<>"']/g, c => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;" }[c])); }
  function toast(message, error = false) {
    clearTimeout(toastTimer); $("#toast").textContent = message; $("#toast").classList.toggle("error", error); $("#toast").hidden = false;
    toastTimer = setTimeout(() => $("#toast").hidden = true, error ? 6500 : 2500);
  }
  function setBusy(value) { busy = value; $("#apply").disabled = value; document.querySelectorAll(".item").forEach(el => el.disabled = value); }
  function applyTheme(value) { document.documentElement.dataset.theme = String(value).toLowerCase() === "dark" ? "dark" : "light"; }
  function renderItems(target, items, kind, emptyText) {
    $(target).innerHTML = items.length ? items.map(item => `<button class="item" data-kind="${kind}" data-index="${item.index}"><span class="number">${item.index}</span><span class="code">${escape(item.code)}</span><span class="symbol">${escape(item.preview)}</span></button>`).join("") : `<div class="empty">${escape(emptyText)}</div>`;
  }
  function resetComposer() {
    setBusy(false);
    selected = null; previewSequence++;
    $("#code-input").value = ""; $("#code-input").classList.remove("invalid");
    $("#preview").textContent = "—"; $("#preview").classList.remove("invalid");
    document.querySelectorAll(".item.selected").forEach(el => el.classList.remove("selected"));
  }
  function render(reset = false) {
    if (!state) return;
    applyTheme(state.theme);
    document.title = state.title; $("#description").textContent = state.description; $("#apply").textContent = state.action;
    $("#mode-badge").textContent = state.mode === "clipboard" ? "Буфер обмена" : "Вставка";
    $("#favorite-shortcut").textContent = state.settings.favoriteShortcut; $("#history-shortcut").textContent = state.settings.historyShortcut;
    $("#confirm").checked = state.settings.confirm; $("#move-history").checked = state.settings.moveHistory;
    $("#history-modifier").value = state.settings.historyModifier; $("#favorite-modifier").value = state.settings.favoriteModifier;
    renderItems("#favorites", state.favorites, "favorite", "Часто используемые последовательности появятся здесь автоматически.");
    renderItems("#history", state.history, "history", "История пока пуста.");
    if (reset) resetComposer();
    selected = null; $("#code-input").focus();
  }
  async function updatePreview() {
    const own = ++previewSequence, input = $("#code-input").value;
    try {
      const result = await request("preview", { input });
      if (own !== previewSequence) return;
      $("#preview").textContent = result.valid ? result.preview : result.empty ? "—" : "Ошибка";
      $("#preview").classList.toggle("invalid", !result.valid && !result.empty);
      $("#code-input").classList.toggle("invalid", !result.valid && !result.empty);
    } catch (error) { if (own === previewSequence) toast(error.message, true); }
  }
  async function applyInput() {
    if (busy) return;
    const input = $("#code-input").value;
    setBusy(true);
    try { await request("applyInput", { input }); }
    catch (error) { toast(error.message, true); $("#code-input").focus(); setBusy(false); }
  }
  async function applyItem(kind, index) {
    if (busy) return;
    setBusy(true);
    try { await request("applyItem", { kind, index }); }
    catch (error) { toast(error.message, true); setBusy(false); }
  }
  function focusItem(kind, index) {
    document.querySelectorAll(".item.selected").forEach(el => el.classList.remove("selected"));
    const item = document.querySelector(`.item[data-kind="${kind}"][data-index="${index}"]`);
    if (!item) return;
    selected = { kind, index }; item.classList.add("selected"); item.focus();
  }
  async function saveSettings(changed) {
    if (!state || busy) return;
    setBusy(true);
    try {
      state = await request("saveSettings", { changed, confirm: $("#confirm").checked, moveHistory: $("#move-history").checked, historyModifier: $("#history-modifier").value, favoriteModifier: $("#favorite-modifier").value });
      render(); toast("Параметры сохранены");
    } catch (error) { toast(error.message, true); render(); }
    finally { setBusy(false); }
  }

  $("#code-input").addEventListener("input", () => { selected = null; updatePreview(); });
  $("#apply").addEventListener("click", applyInput);
  $(".lists").addEventListener("click", event => { const item = event.target.closest(".item"); if (item) applyItem(item.dataset.kind, Number(item.dataset.index)); });
  for (const id of ["confirm", "move-history", "history-modifier", "favorite-modifier"])
    $(`#${id}`).addEventListener("change", () => saveSettings(id.replace("-", "").replace(/^historymodifier$/, "historyModifier").replace(/^favoritemodifier$/, "favoriteModifier")));
  document.addEventListener("keydown", event => {
    if (event.key === "Escape") { event.preventDefault(); request("close").catch(() => {}); }
    else if (event.key === "Enter") {
      event.preventDefault();
      const focusedItem = document.activeElement?.closest?.(".item");
      if (focusedItem) applyItem(focusedItem.dataset.kind, Number(focusedItem.dataset.index));
      else selected ? applyItem(selected.kind, selected.index) : applyInput();
    }
  });

  if (bridge) request("state").then(result => { state = result; render(); }).catch(error => toast(error.message, true));
  else { $("#description").textContent = "Откройте Unicode Input через Layout Toolkit"; $("#apply").disabled = true; }
})();
