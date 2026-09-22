"use strict";
(() => {
  const $ = (selector) => document.querySelector(selector);
  const escape = (value) => String(value ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const titles = { general: "Обзор", layout: "Раскладка", live: "Live-режим", hotkeys: "Горячие клавиши", unicode: "Unicode", caps: "Регистр", exclude: "Исключения", about: "О программе" };
  let state, page = "general", dirty = false, busy = false, sequence = 0, hotkeys = {}, toastTimer;
  const pending = new Map();
  const bridge = window.chrome?.webview;
  function request(command, data = {}) {
    return new Promise((resolve, reject) => {
      if (!bridge) return reject(new Error("Нет соединения с Layout Toolkit"));
      const id = ++sequence;
      const timer = setTimeout(() => { pending.delete(id); reject(new Error("Программа не ответила. Закройте и снова откройте настройки.")); }, 30000);
      pending.set(id, { resolve, reject, timer });
      bridge.postMessage({ id, command, data });
    });
  }
  bridge?.addEventListener("message", ({ data }) => {
    if (pending.has(data.id)) {
      const item = pending.get(data.id);
      pending.delete(data.id); clearTimeout(item.timer);
      data.ok ? item.resolve(data.result) : item.reject(new Error(data.error));
    } else if (data.type === "state" && !dirty && !busy) { state = data.state; render(); }
    else if (data.type === "error") toast(data.message, true);
  });
  function toast(message, error = false) {
    clearTimeout(toastTimer);
    $("#toast").textContent = message;
    $("#toast").classList.toggle("error", error);
    $("#toast").hidden = false;
    toastTimer = setTimeout(() => $("#toast").hidden = true, error ? 9000 : 4000);
  }
  function setDirty(value) { dirty = value; $("#savebar").hidden = !value; }
  function setBusy(value) {
    busy = value;
    document.querySelectorAll("button,input,select").forEach(el => el.disabled = value);
    if (!value && page === "live") updateInterval();
  }
  function applyTheme(value) {
    const dark = String(value).toLowerCase() === "dark";
    const theme = dark ? "Dark" : "Light";
    document.documentElement.dataset.theme = theme.toLowerCase();
    try { localStorage.setItem("lt-theme", theme); } catch {}
    const button = $("#theme-toggle");
    if (button) {
      button.textContent = dark ? "☾ Тёмная тема" : "☀ Светлая тема";
      button.setAttribute("aria-label", dark ? "Переключить на светлую тему" : "Переключить на тёмную тему");
    }
  }
  const action = (name, label, cls = "") => `<button data-action="${name}" class="${cls}">${label}</button>`;
  const key = (name) => `<kbd class="key">${escape(state.hotkeys.find(h => h.action.toLowerCase() === name.toLowerCase())?.display || "Не назначено")}</kbd>`;
  const example = (from, to) => `<div class="example"><code>${escape(from)}</code><span class="arrow">→</span><code>${escape(to)}</code></div>`;
  const toggle = (id, checked, title, note) => `<div class="row"><div><h3><label for="${id}">${title}</label></h3><p>${note}</p></div><input class="toggle" type="checkbox" id="${id}" ${checked ? "checked" : ""}></div>`;
  const shortcut = (id, value, label) => `<div class="field"><label for="${id}">${label}</label><select id="${id}">${["Ctrl", "Shift", "Alt", "Win", "Tab"].map(x => `<option ${x === value ? "selected" : ""}>${x}</option>`).join("")}</select></div>`;
  function render() {
    if (!state) return;
    applyTheme(state.theme);
    $("#version").textContent = `Версия ${state.version}`;
    $("#title").textContent = titles[page];
    document.querySelectorAll("[data-page]").forEach(el => {
      el.classList.toggle("active", el.dataset.page === page);
      if (el.closest("nav")) el.setAttribute("aria-current", el.dataset.page === page ? "page" : "false");
    });
    const views = {
      general: () => `
        <div class="columns"><div class="card"><h3>Live-режим</h3><div class="big-number">${state.live.enabled ? "Включён" : "Выключен"}</div><p>${state.live.trigger === "Hotkey" ? "Исправление по горячей клавише" : "Исправление по двойному пробелу"}</p><div class="actions"><button data-page="live" class="subtle">Настроить →</button></div></div><div class="card"><h3>Личный словарь</h3><div class="big-number">${state.excludeCount}</div><p>исключений для конвертации</p><div class="actions"><button data-page="exclude" class="subtle">Открыть исключения →</button></div></div></div>
        <div class="card"><h2>Всегда под рукой</h2><div class="row"><div><h3>Полная конвертация</h3><p>Исправить раскладку выделенного текста</p></div>${key("layoutFull")}</div><div class="row"><div><h3>CapsLock Full Fix</h3><p>Инверсия регистра с каноничным написанием</p></div>${key("capsLockFullFix")}</div><div class="actions"><button data-page="hotkeys" class="subtle">Все горячие клавиши →</button></div></div>
        <div class="card"><h3>Ваши настройки</h3><p>Хранятся отдельно от файлов программы.</p><div class="path">${escape(state.dataDir)}</div><div class="actions">${action("openData", "Открыть папку")}${action("restart", "Перезапустить Toolkit", "subtle")}</div></div>`,
      layout: () => `<p class="section-note">Два режима для разных задач. Выделите текст и нажмите нужное сочетание.</p><div class="card"><div class="row"><div><h2>Полная конвертация</h2><p>Каждый символ переводится в противоположную раскладку.</p></div>${key("layoutFull")}</div>${example("Ghbdtn/ Rfr ltkf&", "Привет. Как дела?")}<p>Буквы и знаки преобразуются по таблице раскладки, без угадывания смысла.</p></div><div class="card"><div class="row"><div><h2>По большинству</h2><p>Приводит чужие токены к языку большинства.</p></div>${key("layoutMajority")}</div><p>Подходит для смешанного текста. Слова из списка исключений учитываются алгоритмом конвертации.</p></div>`,
      live: () => `<div class="card">${toggle("live-enabled", state.live.enabled, "Исправление во время набора", "Обрабатывает текущий набранный фрагмент.")}${toggle("live-switch-language", state.live.switchInputLanguage, "Переключать раскладку после исправления", "После успешной замены выбрать русскую или английскую раскладку в целевом приложении.")}</div><div class="card live-trigger-card"><h2>Как запускать исправление</h2><p>Выберите один способ запуска: одновременно работает только выбранный вариант.</p><div class="live-trigger-grid"><div><div class="radios"><label><input type="radio" name="trigger" value="DoubleSpace" ${state.live.trigger === "DoubleSpace" ? "checked" : ""}>Двойной пробел</label><label><input type="radio" name="trigger" value="Hotkey" ${state.live.trigger === "Hotkey" ? "checked" : ""}>Горячая клавиша</label></div><div class="field"><label for="live-interval">Интервал между пробелами, мс</label><input id="live-interval" type="number" min="100" max="3000" step="1" value="${state.live.interval}"><p>От 100 до 3000 мс. Меньше значение — быстрее нужно нажать пробел повторно.</p></div></div><div class="live-shortcuts"><div class="row"><div><h3>Исправить фрагмент</h3></div>${key("liveConvert")}</div><div class="row"><div><h3>Включить или выключить Live</h3></div>${key("liveToggle")}</div></div></div></div><div class="card">${toggle("live-hint", state.live.hint, "Подсказка при первом включении", "Показать, как пользоваться Live-режимом.")}</div><div class="hint">Live заменяет текст в активном приложении. Для больших документов удобнее выделение и полная конвертация.</div>`,
      hotkeys: () => `<p class="section-note">Нажмите «Изменить», затем нужное сочетание. Escape отменяет захват.</p><div class="card">${state.hotkeys.map(h => `<div class="row"><div><h3>${escape(h.label)}</h3></div><div class="hotkey-controls"><kbd class="key" id="key-${escape(h.action)}">${escape(h.display || "Не назначено")}</kbd><button data-capture="${escape(h.action)}" aria-label="Изменить: ${escape(h.label)}">Изменить</button></div></div>`).join("")}</div><div class="card"><h3>Расширенные настройки</h3><p>Сочетания также можно изменить в файле hotkeys.ini.</p><div class="actions">${action("openHotkeys", "Открыть файл")}${action("reloadHotkeys", "Перечитать")}${action("resetHotkeys", "По умолчанию", "subtle")}</div></div>`,
      unicode: () => `<div class="card"><div class="row"><div><h2>Символы без поиска по таблицам</h2><p>Поиск, избранное и история вставки.</p></div>${key("unicodeInput")}</div><div class="actions">${action("unicode", "Открыть палитру символов", "primary")}</div></div><div class="card">${toggle("unicode-confirm", state.unicode.confirm, "Подтверждать выбор клавишей Enter", "Выбор по цифре сначала выделяет символ.")}${toggle("unicode-history", state.unicode.moveHistory, "Поднимать использованные символы", "Повторно выбранный символ перемещается в начало истории.")}</div><div class="card"><h2>Быстрый выбор</h2><p>Модификаторы для цифровых сочетаний в палитре. История и избранное должны использовать разные клавиши.</p><div class="columns">${shortcut("unicode-history-key", state.unicode.history, "История")}${shortcut("unicode-favorite-key", state.unicode.favorite, "Избранное")}</div></div>`,
      caps: () => `<p class="section-note">Оба режима работают с выделенным текстом.</p><div class="card"><div class="row"><div><h2>CapsLock Full Fix</h2><p>Прямая инверсия регистра.</p></div>${key("capsLockFullFix")}</div>${example("cORE jAM", "Core Jam")}<p>Строчные становятся прописными, прописные — строчными. Каноничное написание известных слов сохраняется.</p></div><div class="card"><div class="row"><div><h2>CapsLock Fix</h2><p>Умное приведение регистра.</p></div>${key("capsLockFix")}</div>${example("эТО пРИМЕР", "Это пример")}<p>Нормализует регистр текста с учётом начала предложений и словаря каноничных написаний.</p></div>`,
      exclude: () => `<div class="card"><h2>Слова, которые нужно сохранить</h2><p>Названия, сокращения и другие исключения для алгоритмов конвертации.</p><div class="big-number">${state.excludeCount}</div><p>записей загружено</p><div class="path">${escape(state.excludePath)}</div><div class="actions">${action("openExclude", "Редактировать список", "primary")}${action("reloadExclude", "Перечитать список")}</div></div><div class="hint">После редактирования сохраните файл, затем нажмите «Перечитать список», чтобы изменения начали действовать.</div><div class="card"><h3>Заводской список</h3><p>Восстановление заменит ваши исключения стандартными. Перед заменой программа запросит подтверждение.</p><div class="actions">${action("resetExclude", "Восстановить по умолчанию", "danger")}</div></div>`,
      about: () => `<div class="card hero"><span class="tag">LAYOUT TOOLKIT RU / EN</span><h2>Маленький помощник для больших текстов</h2><p>Версия ${escape(state.version)}</p></div><div class="card"><h2>Локальный интерфейс</h2><p>Эти настройки написаны на HTML, CSS и JavaScript и открываются внутри Microsoft Edge WebView2. Интернет для работы интерфейса не нужен.</p><p>Конвертация, горячие клавиши и взаимодействие с Windows по-прежнему выполняются в AutoHotkey.</p></div><div class="card"><h3>Компоненты</h3><p>AutoHotkey v2 · Microsoft Edge WebView2 · thqby/ahk2_lib (MIT).</p><p>Сведения о лицензиях находятся в Modules/Vendor рядом с программой.</p></div>`
    };
    $("#content").innerHTML = views[page]();
    $("#content").dataset.page = page;
    if (page === "hotkeys") hotkeys = Object.fromEntries(state.hotkeys.map(h => [h.action, h.value]));
    if (page === "live") updateInterval();
  }
  function updateInterval() { $("#live-interval").disabled = busy || $("input[name=trigger]:checked")?.value !== "DoubleSpace"; }
  async function save() {
    if (!dirty || busy) return !dirty;
    let data, command;
    if (page === "live") {
      const interval = Number($("#live-interval").value);
      if (!Number.isInteger(interval) || interval < 100 || interval > 3000) { toast("Интервал должен быть целым числом от 100 до 3000 мс", true); return false; }
      command = "saveLive";
      data = { enabled: $("#live-enabled").checked, switchInputLanguage: $("#live-switch-language").checked, hint: $("#live-hint").checked, trigger: $("input[name=trigger]:checked").value, interval };
    } else if (page === "unicode") {
      command = "saveUnicode";
      data = { confirm: $("#unicode-confirm").checked, moveHistory: $("#unicode-history").checked, history: $("#unicode-history-key").value, favorite: $("#unicode-favorite-key").value };
      if (data.history === data.favorite) { toast("Для истории и избранного нужны разные клавиши", true); return false; }
    } else if (page === "hotkeys") { command = "saveHotkeys"; data = hotkeys; }
    else return false;
    setBusy(true);
    try { state = await request(command, data); setDirty(false); render(); toast("Настройки сохранены"); return true; }
    catch (error) { toast(error.message, true); return false; }
    finally { setBusy(false); }
  }
  function resolveUnsaved() {
    return new Promise(resolve => {
      const dialog = $("#unsaved");
      const close = () => { dialog.removeEventListener("close", close); resolve(dialog.returnValue || "stay"); };
      dialog.returnValue = "stay"; dialog.addEventListener("close", close); dialog.showModal();
    });
  }
  async function navigate(next) {
    if (!state || busy || page === next) return;
    if (dirty) {
      const choice = await resolveUnsaved();
      if (choice === "stay" || choice === "save" && !(await save())) return;
    }
    page = next; setDirty(false); render(); $("#content").scrollTop = 0;
  }
  document.addEventListener("click", async event => {
    const button = event.target.closest("button");
    if (!button || button.disabled) return;
    if (button.id === "theme-toggle") {
      const theme = document.documentElement.dataset.theme === "dark" ? "Light" : "Dark";
      button.disabled = true;
      try {
        const result = await request("saveTheme", { theme });
        state.theme = result.theme;
        applyTheme(result.theme);
      } catch (error) { toast(error.message, true); }
      finally { button.disabled = false; }
      return;
    }
    if (button.dataset.choice) { $("#unsaved").close(button.dataset.choice); return; }
    if (button.dataset.page) { await navigate(button.dataset.page); return; }
    if (button.id === "save") { await save(); return; }
    if (button.id === "discard") { setDirty(false); render(); return; }
    if (button.dataset.capture) {
      const name = button.dataset.capture, previous = button.textContent;
      setBusy(true); button.textContent = "Нажмите клавиши…";
      toast("Нажмите сочетание в течение 10 секунд. Escape — отмена.");
      try {
        const result = await request("capture", { action: name });
        if (!result.cancelled) { hotkeys[name] = result.value; $(`#key-${name}`).textContent = result.display; setDirty(true); toast("Сочетание выбрано. Нажмите «Сохранить»."); }
        else toast("Захват отменён");
      } catch (error) { toast(error.message, true); }
      finally { button.textContent = previous; setBusy(false); }
      return;
    }
    if (button.dataset.action) {
      const name = button.dataset.action;
      if (dirty && ["reloadHotkeys", "resetHotkeys", "restart"].includes(name)) { toast("Сначала сохраните или отмените изменения", true); return; }
      setBusy(true);
      try { const result = await request("action", { name }); if (!dirty) { state = result; render(); } }
      catch (error) { toast(error.message, true); }
      finally { setBusy(false); }
    }
  });
  $("#content").addEventListener("input", event => {
    if (!busy && event.target.matches("input,select")) { setDirty(true); if (page === "live") updateInterval(); }
  });
  try { applyTheme(localStorage.getItem("lt-theme") || "Light"); } catch { applyTheme("Light"); }
  if (bridge) request("state").then(result => { state = result; render(); bridge.postMessage({ command: "uiReady" }); }).catch(error => { $("#content").textContent = error.message; });
  else $("#content").innerHTML = '<div class="card empty">Откройте настройки через Layout Toolkit.</div>';
})();
