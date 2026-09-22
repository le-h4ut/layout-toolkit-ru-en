; Appended to an isolated production runtime by Run-LiveInputLanguageTests.ps1.
LiveTest_Assert(condition, label) {
    if !condition
        throw Error("FAIL: " label)
}

RunLiveInputLanguageTests() {
    global g_LiveTestIgnoreAll := false
    try {
        LiveTest_Assert(GetInstalledKeyboardLayouts() is Array, "Windows keyboard-layout enumeration returns an array")
        LiveTest_Assert(GetLiveInputTargetHwnd(0) = 0, "invalid target window has no focused HWND")
        layouts := [0x00000809, 0x00000419]
        LiveTest_Assert(FindInstalledKeyboardLayout("RU_TO_EN", layouts) = 0x00000809, "installed British English HKL is selected without assuming US English")
        LiveTest_Assert(FindInstalledKeyboardLayout("EN_TO_RU", layouts) = 0x00000419, "installed Russian HKL is selected")
        LiveTest_Assert(FindInstalledKeyboardLayout("UNKNOWN", layouts) = 0, "unknown direction has no HKL")

        LiveTest_RunCase("hotkey EN to RU", "Hotkey", "Ghbdtn", true, true, false, false, false, true, 0x00000419)
        LiveTest_RunCase("hotkey RU to EN", "Hotkey", "Привет", true, true, false, false, false, true, 0x00000809)
        LiveTest_RunCase("double-space EN to RU", "DoubleSpace", "Ghbdtn  ", true, true, false, false, false, true, 0x00000419)
        LiveTest_RunCase("double-space RU to EN", "DoubleSpace", "Привет  ", true, true, false, false, false, true, 0x00000809)
        LiveTest_RunCase("queued text is released once", "DoubleSpace", "Ghbdtn  ", true, true, false, false, false, true, 0x00000419, "мир", "мир")
        LiveTest_RunCase("fast typing stays unchanged when switching is disabled", "Hotkey", "Ghbdtn", false, true, false, false, false, true, 0, "vbh", "vbh")
        LiveTest_RunCase("setting disabled", "Hotkey", "Ghbdtn", false, true, false, false, false, true, 0)
        LiveTest_RunCase("mixed alphabets inside a token are not destructively converted", "Hotkey", "abвг", true, true, false, false, false, false, 0)
        LiveTest_RunCase("clipboard unavailable does not affect Unicode replacement", "Hotkey", "Ghbdtn", true, false, false, false, false, true, 0x00000419)
        LiveTest_RunCase("text replacement failed", "Hotkey", "Ghbdtn", true, true, true, false, false, false, 0)
        LiveTest_RunCase("active window changed", "DoubleSpace", "Ghbdtn  ", true, true, false, true, false, true, 0)
        LiveTest_RunCase("layout request failed", "Hotkey", "Ghbdtn", true, true, false, false, true, true, 0)
        LiveTest_VerifyFocusedWindowFallback()
        LiveTest_Regressions()

        FileAppend("PASS: Live input-language switching for both directions and triggers, disabled, failed and changed-window paths`n", "*", "UTF-8")
        ExitApp(0)
    } catch as err {
        FileAppend(err.Message "`n" err.Stack "`n", "**", "UTF-8")
        ExitApp(1)
    }
}

LiveTest_VerifyFocusedWindowFallback() {
    global g_LiveSwitchInputLanguage := true
    global g_LiveTestActiveWindow := 100
    global g_LiveTestPostThrows := false
    global g_LiveTestRequests := []
    global g_LiveTestCurrentHkl := 0
    global g_LiveTestIgnoreFirstLayoutRequest := true
    global g_LiveTestEvents := []

    LiveTest_Assert(TrySwitchLiveInputLanguage(100, "EN_TO_RU"), "focused-window fallback reports a posted request")
    LiveTest_Assert(g_LiveTestRequests.Length = 2, "ignored focused-window request retries once")
    LiveTest_Assert(g_LiveTestRequests[1][1] = 777 && g_LiveTestRequests[2][1] = 100, "fallback targets focused HWND before top-level HWND")
    g_LiveTestIgnoreFirstLayoutRequest := false
}

LiveTest_RunCase(label, trigger, rawFragment, enabled, clipboardReady, sendThrows, changeWindowOnSend, postThrows, expectedSuccess, expectedHkl, pendingDuringSend := "", expectedPendingOutput := "") {
    global g_LiveSwitchInputLanguage := enabled
    global g_LiveBusy := true
    global g_LivePendingBuffer := ""
    global g_LiveContextInvalidated := false
    global g_LiveOperationWindow := 100
    global g_LiveBoundarySourcePrefix := ""
    global g_LiveBoundaryReplacementPrefix := ""
    global g_LastWindow := 100
    global g_Buffer := rawFragment
    global g_LiveTestClipboard := "original clipboard"
    global g_LiveTestClipboardReady := clipboardReady
    global g_LiveTestActiveWindow := 100
    global g_LiveTestChangeWindowOnSend := changeWindowOnSend
    global g_LiveTestSendThrows := sendThrows
    global g_LiveTestPostThrows := postThrows
    global g_LiveTestRequests := []
    global g_LiveTestCurrentHkl := 0
    global g_LiveTestIgnoreFirstLayoutRequest := false
    global g_LiveTestEvents := []
    global g_LiveTestPendingDuringSend := pendingDuringSend
    global g_LiveTestPendingOutputs := []
    global g_LiveTestInputBuffering := false

    LiveTest_SetInputBuffering(true)

    result := trigger = "Hotkey"
        ? TryLiveConvertHotkey(rawFragment, 100)
        : TryLiveConvertDoubleSpace(rawFragment, 100)

    LiveTest_Assert(result = expectedSuccess, label ": conversion result")
    LiveTest_Assert(!g_LiveBusy, label ": busy flag released")
    LiveTest_Assert(!g_LiveTestInputBuffering, label ": physical text released")
    LiveTest_Assert(g_LiveTestClipboard = "original clipboard", label ": clipboard restored")

    if (expectedPendingOutput != "") {
        LiveTest_Assert(g_LiveTestPendingOutputs.Length = 1, label ": pending text released once")
        LiveTest_Assert(g_LiveTestPendingOutputs[1] = expectedPendingOutput, label ": pending text normalized to target layout")
        LiveTest_Assert(g_Buffer = expectedPendingOutput, label ": typing buffer follows released text")
    }

    if expectedHkl {
        LiveTest_Assert(g_LiveTestRequests.Length = 1, label ": one layout request")
        LiveTest_Assert(g_LiveTestRequests[1][1] = 777, label ": focused child HWND used")
        LiveTest_Assert(g_LiveTestRequests[1][2] = expectedHkl, label ": expected installed HKL used")
        LiveTest_Assert(g_LiveTestEvents[1] = "send" && g_LiveTestEvents[2] = "post", label ": layout request follows Unicode replacement")
    } else {
        LiveTest_Assert(g_LiveTestRequests.Length = 0, label ": no layout request")
    }
}

LiveTest_ClipboardAll() {
    global g_LiveTestClipboard
    return g_LiveTestClipboard
}

LiveTest_ClipWait(*) {
    global g_LiveTestClipboardReady
    return g_LiveTestClipboardReady
}

LiveTest_Send(*) {
    global g_LiveTestActiveWindow, g_LiveTestChangeWindowOnSend, g_LiveTestSendThrows, g_LiveTestEvents
    global g_LiveTestPendingDuringSend, g_LivePendingBuffer
    if g_LiveTestSendThrows
        throw Error("simulated text replacement failure")
    g_LiveTestEvents.Push("send")
    if (g_LiveTestPendingDuringSend != "")
        g_LivePendingBuffer .= g_LiveTestPendingDuringSend
    if g_LiveTestChangeWindowOnSend
        g_LiveTestActiveWindow := 200
}

LiveTest_SendPending(text) {
    global g_LiveTestPendingOutputs, g_LiveTestEvents
    g_LiveTestPendingOutputs.Push(text)
    g_LiveTestEvents.Push("pending-send")
}

LiveTest_SetInputBuffering(enabled) {
    global g_LiveTestInputBuffering := enabled
}

LiveTest_WinExist() {
    global g_LiveTestActiveWindow
    return g_LiveTestActiveWindow
}

LiveTest_FindInstalledKeyboardLayout(direction) {
    return direction = "EN_TO_RU" ? 0x00000419 : direction = "RU_TO_EN" ? 0x00000809 : 0
}

LiveTest_GetLiveInputTargetHwnd(*) {
    return 777
}

LiveTest_PostInputLanguageRequest(inputWindow, hkl) {
    global g_LiveTestRequests, g_LiveTestPostThrows, g_LiveTestCurrentHkl, g_LiveTestIgnoreFirstLayoutRequest, g_LiveTestEvents
    global g_LiveTestIgnoreAll
    if g_LiveTestPostThrows
        throw Error("simulated PostMessage failure")
    g_LiveTestEvents.Push("post")
    g_LiveTestRequests.Push([inputWindow, hkl])
    if !g_LiveTestIgnoreAll && !(g_LiveTestIgnoreFirstLayoutRequest && g_LiveTestRequests.Length = 1)
        g_LiveTestCurrentHkl := hkl
    return true
}

LiveTest_Regressions() {
    global g_LiveTestIgnoreAll := true
    global g_LiveTestCurrentHkl := 0x409
    global g_LiveContextInvalidated := false
    global g_LiveOperationWindow := 100
    global g_LiveOperationFocus := 0
    global g_LivePendingDirection := ""
    global g_LiveBusy := true
    global g_LivePendingBuffer := ""
    global g_LiveRecoveryBuffer := ""
    global g_LiveTestActiveWindow := 100
    global g_Buffer
    LiveTest_Assert(!TrySwitchLiveInputLanguage(100, "EN_TO_RU"), "ignored request never reports confirmed switch")
    g_LiveTestIgnoreAll := false
    Loop 301
        AppendLivePendingChar("a")
    LiveTest_Assert(StrLen(g_LivePendingBuffer) = 301, "hidden text is not truncated")
    HandleLiveContextBreak()
    LiveTest_Assert(StrLen(g_LiveRecoveryBuffer) = 301, "context break preserves hidden text for recovery")
    LiveTest_Assert(g_LivePendingBuffer = "", "recovered text is not sent to new context")
    for item in [
        ["Hello world/ Ghbdtn vbh", "/ Ghbdtn vbh"],
        ["Hello world. Ghbdtn vbh", ". Ghbdtn vbh"],
        ["Привет [kt, vbh", "[kt, vbh"],
        ["Ghbdtn`n`nvbh", "vbh"],
        ["Привет Ghbdtn", "Ghbdtn"],
        ["Hello руддщ", "руддщ"]
    ] {
        g_Buffer := item[1]
        ClearLiveBoundaryPrefix()
        RecalculateBufferState()
        LiveTest_Assert(g_Buffer = item[2], "fragment boundary: " item[1])
    }
    g_LiveBusy := false
}

LiveTest_GetWindowKeyboardLayout(*) {
    global g_LiveTestCurrentHkl
    return g_LiveTestCurrentHkl
}

LiveTest_NoOp(values*) {
    global g_LiveTestEvents
    if (values.Length = 1 && (values[1] = 450 || values[1] = 60))
        g_LiveTestEvents.Push("sleep:" values[1])
}
