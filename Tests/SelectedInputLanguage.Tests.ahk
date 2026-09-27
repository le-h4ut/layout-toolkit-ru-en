; Synthetic selection tests: production handlers, no real clipboard/input.
SelectedTest_Run() {
    for mode in ["Full", "Majority"] {
        enText := mode = "Full" ? "Ghbdtn vbh" : "Привет мир Ghbdtn"
        ruText := mode = "Full" ? "Привет мир" : "Hello world руддщ"
        SelectedTest_Case(mode " EN to RU", mode, enText, true, "", true, 0x419)
        SelectedTest_Case(mode " RU to EN", mode, ruText, true, "", true, 0x809)
        SelectedTest_Case(mode " disabled", mode, enText, false, "", true, 0)
        SelectedTest_Case(mode " copy failed", mode, enText, true, "copy", false, 0)
        SelectedTest_Case(mode " prepare failed", mode, enText, true, "prepare", false, 0)
        SelectedTest_Case(mode " paste failed", mode, enText, true, "paste", false, 0)
        SelectedTest_Case(mode " window changed before paste", mode, enText, true, "copyWindow", false, 0)
        SelectedTest_Case(mode " window changed after paste", mode, enText, true, "pasteWindow", true, 0)
        SelectedTest_Case(mode " focus changed after paste", mode, enText, true, "pasteFocus", true, 0)
        SelectedTest_Case(mode " request rejected", mode, enText, true, "post", true, 0)
        SelectedTest_Case(mode " no installed HKL", mode, enText, true, "noLayout", true, 0)
        SelectedTest_Case(mode " unchanged", mode, "12345", true, "", false, 0)
    }
    SelectedTest_Case("Full ambiguous mixed text", "Full", "Ghbdtn Привет", true, "", true, 0)
    SelectedTest_Case("Full ambiguous mixed token", "Full", "abвг", true, "", true, 0)
    SelectedTest_Case("Full preserved exception does not make direction ambiguous", "Full", "Ghbdtn USB", true, "", true, 0x419)
    SelectedTest_Case("Full Unicode prefix preserves direction", "Full", "🙂 Ghbdtn", true, "", true, 0x419)
    SelectedTest_Case("Full letter to punctuation still has a direction", "Full", "ю", true, "", true, 0x809)
    SelectedTest_Case("Majority equal counts", "Majority", "abc абв", true, "", false, 0)
    SelectedTest_VerifyBusyGuard()
    FileAppend("PASS: Full/Majority directions, shared setting, ambiguous text, failures, missing HKL and target guards`n", "*", "UTF-8")
}

SelectedTest_VerifyBusyGuard() {
    global g_SelectedConversionBusy := true, g_LiveBusy := false
    global g_LiveEnabled := true, g_LiveTriggerMode := "Hotkey"
    LiveTest_Assert(!ConvertSelectedFullHotkey(), "selection cannot reenter while busy")
    LiveConvertHotkeyPressed()
    LiveTest_Assert(!g_LiveBusy, "Live hotkey cannot overlap a selection transaction")
    g_LiveTriggerMode := "DoubleSpace"
    LiveSpacePressed()
    LiveTest_Assert(!g_LiveBusy, "double space cannot overlap a selection transaction")
    g_SelectedConversionBusy := false
}

SelectedTest_Case(label, mode, text, enabled, failure, expectedSuccess, expectedHkl) {
    global g_SwitchInputLanguageAfterConversion := enabled
    global g_SelectedConversionBusy := false, g_LiveBusy := false
    ; A finished/interrupted Live operation must not poison selection conversion.
    global g_LiveContextInvalidated := true, g_LiveOperationFocus := 999
    global g_LiveTestActiveWindow := 100, g_LiveTestFocusHwnd := 777
    global g_LiveTestClipboard := "CLIPBOARD_SENTINEL"
    global g_LiveTestClipboardReady := failure != "copy"
    global g_LiveTestPostThrows := failure = "post"
    global g_LiveTestNoLayout := failure = "noLayout"
    global g_LiveTestIgnoreAll := false, g_LiveTestIgnoreFirstLayoutRequest := false
    global g_LiveTestRequests := [], g_LiveTestEvents := [], g_LiveTestCurrentHkl := 0
    global g_SelectionTestText := text, g_SelectionTestFailure := failure
    global g_SelectionTestActive := true, g_SelectionTestClipWaitCount := 0
    global g_SelectionTestPrepareFails := failure = "prepare"
    global g_SelectionTestPastes := 0
    global g_SelectionTestError := ""

    result := mode = "Full" ? ConvertSelectedFullHotkey() : ConvertSelectedMajorityHotkey()
    LiveTest_Assert(result = expectedSuccess, label ": result; " g_SelectionTestError)
    LiveTest_Assert(!g_SelectedConversionBusy, label ": busy flag released")
    LiveTest_Assert(g_LiveTestClipboard = "CLIPBOARD_SENTINEL", label ": clipboard restored")
    LiveTest_Assert(g_SelectionTestPastes = (expectedSuccess ? 1 : 0), label ": no premature paste")
    if expectedHkl {
        LiveTest_Assert(g_LiveTestRequests.Length = 1, label ": one request")
        LiveTest_Assert(g_LiveTestRequests[1][1] = 777 && g_LiveTestRequests[1][2] = expectedHkl, label ": focused HWND and installed HKL")
        LiveTest_Assert(g_LiveTestEvents[1] = "paste" && g_LiveTestEvents[2] = "post", label ": request follows replacement")
    } else
        LiveTest_Assert(g_LiveTestRequests.Length = 0, label ": no successful layout request")
    g_SelectionTestActive := false
}

SelectedTest_Copy() {
    global g_LiveTestClipboard, g_SelectionTestText, g_SelectionTestFailure, g_LiveTestActiveWindow
    g_LiveTestClipboard := g_SelectionTestText
    if g_SelectionTestFailure = "copyWindow"
        g_LiveTestActiveWindow := 200
}

SelectedTest_RecordError(err) {
    global g_SelectionTestError := err.Message " " err.Stack
}

SelectedTest_Paste() {
    global g_SelectionTestFailure, g_SelectionTestPastes, g_LiveTestEvents
    global g_LiveTestActiveWindow, g_LiveTestFocusHwnd
    if g_SelectionTestFailure = "paste"
        throw Error("simulated paste failure")
    g_SelectionTestPastes++
    g_LiveTestEvents.Push("paste")
    if g_SelectionTestFailure = "pasteWindow"
        g_LiveTestActiveWindow := 200
    if g_SelectionTestFailure = "pasteFocus"
        g_LiveTestFocusHwnd := 888
}
