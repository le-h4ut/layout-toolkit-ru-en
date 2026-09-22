(async () => {
  const rerun = !!window.__ltBrowserCompletedOnce;
  const $ = s => document.querySelector(s);
  const layoutErrors = [];
  const assert = (ok, message) => { if (!ok) throw new Error(message); };
  const until = async predicate => {
    const deadline = Date.now() + 5000;
    while (!predicate()) {
      if (Date.now() > deadline) throw new Error("UI condition timed out");
      await new Promise(resolve => setTimeout(resolve, 25));
    }
  };
  const input = (selector, value) => {
    $(selector).value = value;
    $(selector).dispatchEvent(new Event("input", { bubbles: true }));
  };
  const navigate = async (name, title) => {
    $(`nav [data-page=${name}]`).click();
    await until(() => $("#title").textContent === title);
    assert(document.documentElement.scrollWidth <= innerWidth, `No page overflow: ${name}`);
    assert($("main").scrollWidth <= $("main").clientWidth + 1, `No content overflow: ${name}`);
    assert($("#content").scrollWidth <= $("#content").clientWidth + 1, `No horizontal scrolling: ${name}`);
    if (innerWidth >= 800 && innerHeight >= 540)
      if ($("#content").scrollHeight > $("#content").clientHeight + 1)
        layoutErrors.push(`${name} (${$("#content").scrollHeight}/${$("#content").clientHeight})`);
  };
  try {
    await navigate("general", "Обзор");
    assert(document.documentElement.dataset.theme === "light", "Light theme is the default");
    assert($("#theme-toggle").textContent.includes("Светлая"), "Theme switch is visible in the header");
    $("#theme-toggle").click();
    await until(() => document.documentElement.dataset.theme === "dark" && !$("#theme-toggle").disabled);
    assert($("#theme-toggle").textContent.includes("Тёмная"), "Dark theme is applied and named");
    $("#theme-toggle").click();
    await until(() => document.documentElement.dataset.theme === "light" && !$("#theme-toggle").disabled);
    assert($("#content").textContent.includes("Win+F12"), "Real hotkey from AHK state");
    for (const [name, title] of Object.entries({ layout: "Раскладка", live: "Live-режим", hotkeys: "Горячие клавиши", unicode: "Unicode", caps: "Регистр", exclude: "Исключения", about: "О программе", general: "Обзор" })) await navigate(name, title);
    await navigate("live", "Live-режим");
    assert($("#live-switch-language").checked === rerun, rerun ? "Live layout switch persists" : "Live layout switch defaults to off");
    const liveColumns = document.querySelectorAll(".live-trigger-grid > div");
    assert(liveColumns.length === 2 && liveColumns[0].getBoundingClientRect().right <= liveColumns[1].getBoundingClientRect().left, "Live controls use two non-overlapping columns");
    $("#live-switch-language").checked = true;
    $("#live-switch-language").dispatchEvent(new Event("input", { bubbles: true }));
    input("#live-interval", "99");
    const saveRect = $("#save").getBoundingClientRect();
    assert(saveRect.bottom <= innerHeight && saveRect.right <= innerWidth, "Save stays inside the resized window");
    $("#save").click();
    assert(!$("#savebar").hidden, "Invalid interval preserves draft");
    assert($("#toast").classList.contains("error"), "Invalid interval displays error");
    input("#live-interval", "650");
    $("#save").click();
    await until(() => $("#savebar").hidden && !$("#save").disabled);
    assert($("#live-interval").value === "650", "Saved value returned through native bridge");
    assert($("#live-switch-language").checked, "Live layout switch persisted through native bridge");
    input("#live-interval", "750");
    $("nav [data-page=unicode]").click();
    await until(() => $("#unsaved").open);
    $("[data-choice=stay]").click();
    await until(() => !$("#unsaved").open);
    assert($("#title").textContent === "Live-режим", "Stay preserves section");
    $("nav [data-page=unicode]").click();
    await until(() => $("#unsaved").open);
    $("[data-choice=discard]").click();
    await until(() => $("#title").textContent === "Unicode");
    input("#unicode-history-key", "Alt");
    input("#unicode-favorite-key", "Alt");
    $("#save").click();
    assert(!$("#savebar").hidden, "Duplicate modifier preserves draft");
    input("#unicode-favorite-key", "Ctrl");
    $("#save").click();
    await until(() => $("#savebar").hidden && !$("#save").disabled);
    assert($("#unicode-history-key").value === "Alt", "Unicode choice persisted");
    await navigate("live", "Live-режим");
    assert($("#live-interval").value === "650", "Discarded value not persisted");
    await navigate("hotkeys", "Горячие клавиши");
    assert(document.querySelectorAll("[data-capture]").length === 7, "All seven capture buttons");
    assert([...document.querySelectorAll("[data-capture]")].map(el => el.dataset.capture).join(",") === "LayoutFull,LayoutMajority,LiveToggle,LiveConvert,UnicodeInput,CapsLockFix,CapsLockFullFix", "Original native hotkey order");
    assert($("#content").scrollHeight <= $("#content").clientHeight + 1, "Hotkeys fit even at minimum size");
    const firstKey = $(".hotkey-controls .key");
    const originalKey = firstKey.textContent;
    firstKey.textContent = "Win+Ctrl+Shift+Alt+Browser_Favorites";
    for (const row of document.querySelectorAll("#content .row")) {
      const label = row.firstElementChild.getBoundingClientRect();
      const controls = row.lastElementChild.getBoundingClientRect();
      assert(label.right <= controls.left, "Hotkey label does not overlap controls");
      assert(controls.right <= $("#content").getBoundingClientRect().right, "Long hotkey stays inside content");
    }
    firstKey.textContent = originalKey;
    assert(!layoutErrors.length, `Default-size scrolling: ${layoutErrors.join(", ")}`);
    window.__ltBrowserCompletedOnce = true;
    window.__ltTestResult = { ok: true, message: "All browser tests passed" };
  } catch (error) { window.__ltTestResult = { ok: false, message: error.stack || error.message }; }
})();
