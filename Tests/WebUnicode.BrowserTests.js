(async () => {
  const $ = selector => document.querySelector(selector);
  const assert = (ok, message) => { if (!ok) throw new Error(message); };
  const until = async predicate => {
    const deadline = Date.now() + 5000;
    while (!predicate()) {
      if (Date.now() > deadline) throw new Error("UI condition timed out");
      await new Promise(resolve => setTimeout(resolve, 25));
    }
  };
  const enter = async value => {
    $("#code-input").value = value;
    $("#code-input").dispatchEvent(new Event("input", { bubbles: true }));
    await new Promise(resolve => setTimeout(resolve, 80));
  };
  const change = async (selector, value) => {
    $(selector).value = value;
    $(selector).dispatchEvent(new Event("change", { bubbles: true }));
    await until(() => !$("#apply").disabled);
  };
  try {
    assert(document.documentElement.dataset.theme === "dark", "Shared dark theme rendered");
    assert($("#mode-badge").textContent === "Буфер обмена", "Clipboard mode rendered");
    assert(document.querySelectorAll("#favorites .item").length === 2, "Two automatic favorites rendered");
    assert(document.querySelectorAll("#history .item").length === 3, "Three history items rendered");
    assert($("#favorite-shortcut").textContent === "Shift+1…5", "Favorite shortcut rendered");
    assert($("#history-shortcut").textContent === "Ctrl+1…5", "History shortcut rendered");
    await enter("фи");
    await until(() => $("#preview").textContent === "«");
    assert(!$("#code-input").classList.contains("invalid"), "Russian-layout HEX accepted");
    await enter("GG");
    await until(() => $("#preview").textContent === "Ошибка");
    assert($("#code-input").classList.contains("invalid"), "Invalid HEX marked");
    await enter("0060 2014 0060");
    await until(() => $("#preview").textContent === "`—`");
    $("#options").open = true;
    await change("#favorite-modifier", "Ctrl");
    assert($("#history-modifier").value === "Shift" && $("#favorite-modifier").value === "Ctrl", "Duplicate modifier swaps assignments");
    await change("#favorite-modifier", "Shift");
    assert($("#history-modifier").value === "Ctrl" && $("#favorite-modifier").value === "Shift", "Modifier assignments restored");
    $("#confirm").click();
    await until(() => !$("#apply").disabled);
    assert(!$("#confirm").checked, "Confirm setting saved");
    $("#confirm").click();
    await until(() => !$("#apply").disabled);
    assert($("#confirm").checked, "Confirm setting restored");
    const contentRight = document.documentElement.clientWidth;
    for (const item of document.querySelectorAll(".item")) assert(item.getBoundingClientRect().right <= contentRight, "List item stays inside window");
    assert(document.documentElement.scrollWidth <= innerWidth, "No horizontal page overflow");
    assert(document.documentElement.scrollHeight <= innerHeight, `No vertical page overflow (${document.documentElement.scrollHeight}/${innerHeight})`);
    assert($("#apply").getBoundingClientRect().right <= innerWidth, "Apply button stays visible");
    window.__ltUnicodeTestResult = { ok: true, message: "All Unicode browser tests passed" };
  } catch (error) { window.__ltUnicodeTestResult = { ok: false, message: error.stack || error.message }; }
})();
