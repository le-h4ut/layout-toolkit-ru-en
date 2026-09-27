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
    assert($("#switch-language").checked === rerun, "Shared layout switch defaults off and persists");
    $("#switch-language").checked = true;
    $("#switch-language").dispatchEvent(new Event("input", { bubbles: true }));
    $("#save").click();
    await until(() => $("#savebar").hidden && !$("#save").disabled);
    assert($("#switch-language").checked, "General layout switch saved through native bridge");
    for (const [name, title] of Object.entries({ layout: "Раскладка", live: "Live-режим", hotkeys: "Горячие клавиши", unicode: "Unicode", caps: "Регистр", exclude: "Исключения", installation: "Установка", about: "О программе", general: "Обзор" })) await navigate(name, title);
    await navigate("about", "О программе");
    const aboutButton = $("nav [data-page=about]").getBoundingClientRect();
    const aboutIcon = $("nav [data-page=about] svg").getBoundingClientRect();
    assert(aboutIcon.width === 18 && aboutIcon.height === 18 && Math.abs((aboutIcon.top + aboutIcon.bottom) / 2 - (aboutButton.top + aboutButton.bottom) / 2) <= 0.5, "About icon has a square viewport and is vertically centered");
    assert($("[data-action=openProject]").textContent === "Проект на GitHub", "About provides a GitHub project action");
    assert($("#project-website").disabled && $("#project-website").textContent.includes("Coming soon..."), "Website placeholder is inactive");
    await navigate("installation", "Установка");
    assert(!$("#check-update").disabled, "Manual copy can check updates without install.json");
    $("#check-update").click();
    await until(() => !$("#check-update").disabled && $("#update-status").textContent.includes("актуальная"));
    assert($("#install-update").hidden, "Same-version manifest does not offer installation");
    assert($("#content").textContent.includes("Папка программы"), "Installation page shows program folder");
    await navigate("live", "Live-режим");
    assert(!$("#live-switch-language"), "Live has no duplicate shared toggle");
    const liveColumns = document.querySelectorAll(".live-trigger-grid > div");
    assert(liveColumns.length === 2 && liveColumns[0].getBoundingClientRect().right <= liveColumns[1].getBoundingClientRect().left, "Live controls use two non-overlapping columns");
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
    await navigate("general", "Обзор");
    assert($("#switch-language").checked, "Live save preserves the shared layout switch");
    await navigate("live", "Live-режим");
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
