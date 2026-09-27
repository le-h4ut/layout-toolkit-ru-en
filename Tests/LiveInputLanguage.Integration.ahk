; Appended to an isolated production runtime by Run-LiveInputLanguageTests.ps1 -RealInput.
#MaxThreadsPerHotkey 2
LiveIntegration_Assert(condition, label) {
    if !condition
        throw Error("FAIL: " label)
}

LiveTest_NoOp(*) {
}

RunLiveInputLanguageIntegrationTests() {
    global g_SwitchInputLanguageAfterConversion := true
    global g_LiveEnabled := true
    global g_ShowTrayTips := false
    global ih

    try {
        ih := InputHook("V L0 I1")
        ih.OnChar := IH_OnChar
        ih.OnKeyDown := IH_OnKeyDown
        ih.NotifyNonText := true
        ih.Start()
        testGui := Gui("+AlwaysOnTop", "Layout Toolkit Live integration test")
        testEdit := testGui.AddEdit("w480 h100")
        testGui.Show("x-30000 y-30000 w520 h140")
        WinActivate("ahk_id " testGui.Hwnd)
        if !WinWaitActive("ahk_id " testGui.Hwnd, , 2)
            throw Error("FAIL: test input window did not become active")

        LiveIntegration_RunCase(testGui, testEdit, "DoubleSpace", "Ghbdtn  ", "Привет ", "EN_TO_RU")
        LiveIntegration_RunCase(testGui, testEdit, "Hotkey", "Ghbdtn", "Привет", "EN_TO_RU")
        LiveIntegration_RunCase(testGui, testEdit, "DoubleSpace", "Привет  ", "Ghbdtn ", "RU_TO_EN")
        LiveIntegration_RunCase(testGui, testEdit, "Hotkey", "Привет", "Ghbdtn", "RU_TO_EN")
        LiveIntegration_RunFastTypingCase(testGui, testEdit)
        LiveIntegration_RunFastTypingCase(testGui, testEdit, "{vkDB}{vk4B}{vk54}{vkBC}", "хлеб")
        LiveIntegration_RunFastTypingCase(testGui, testEdit, "{vk56}{vk42}{Backspace}{vk48}", "мр")
        LiveIntegration_RunFastTypingCase(testGui, testEdit, "{vk57}{vk4F}{vk52}{vk4C}{vk44}", "world", true)
        LiveIntegration_EndToEnd(testGui, testEdit, "DoubleSpace")
        LiveIntegration_EndToEnd(testGui, testEdit, "Hotkey")
        LiveIntegration_FocusChange(testGui, testEdit)
        SelectedIntegration_Run(testGui, testEdit)

        testGui.Destroy()
        FileAppend("PASS: real Edit control preserves converted text and switches its RU/EN input language`n", "*", "UTF-8")
        ExitApp(0)
    } catch as err {
        FileAppend(err.Message "`n" err.Stack "`n", "**", "UTF-8")
        ExitApp(1)
    }
}

RunSelectedInputLanguageIntegrationTests() {
    global g_LiveEnabled := false, g_ShowTrayTips := false, ih
    oldClipboard := ClipboardAll()
    ih := InputHook("V L0 I1")
    testGui := Gui("+AlwaysOnTop", "Layout Toolkit selection integration test")
    testEdit := testGui.AddEdit("w480 h100")
    exitCode := 0
    try {
        testGui.Show("x-30000 y-30000 w520 h140")
        WinActivate("ahk_id " testGui.Hwnd)
        if !WinWaitActive("ahk_id " testGui.Hwnd, , 2)
            throw Error("test input window did not become active")
        A_Clipboard := "CLIPBOARD_SENTINEL"
        SelectedIntegration_Run(testGui, testEdit)
        LiveIntegration_Assert(A_Clipboard = "CLIPBOARD_SENTINEL", "selection clipboard restored")
    } catch as err {
        FileAppend(err.Message "`n" err.Stack "`n", "**", "UTF-8")
        exitCode := 1
    } finally {
        testGui.Destroy()
        A_Clipboard := oldClipboard
    }
    ExitApp(exitCode)
}

SelectedIntegration_Run(testGui, testEdit) {
    global g_SwitchInputLanguageAfterConversion, g_LiveEnabled, ih
    g_LiveEnabled := false
    ih.Stop()
    for item in [
        ["Full", "Ghbdtn vbh", "Привет мир", "EN_TO_RU"],
        ["Full", "Привет мир", "Ghbdtn vbh", "RU_TO_EN"],
        ["Majority", "Привет мир Ghbdtn", "Привет мир Привет", "EN_TO_RU"],
        ["Majority", "Hello world руддщ", "Hello world hello", "RU_TO_EN"]
    ] {
        g_SwitchInputLanguageAfterConversion := true
        sourceDirection := item[4] = "EN_TO_RU" ? "RU_TO_EN" : "EN_TO_RU"
        DllCall("ActivateKeyboardLayout", "Ptr", FindInstalledKeyboardLayout(sourceDirection), "UInt", 0, "Ptr")
        testEdit.Value := item[2]
        testEdit.Focus()
        Send "^a"
        result := item[1] = "Full" ? ConvertSelectedFullHotkey() : ConvertSelectedMajorityHotkey()
        LiveIntegration_Assert(result && testEdit.Value == item[3], item[1] ": real selected text replaced; actual=" testEdit.Value)
        LiveIntegration_Assert(KeyboardLayoutMatchesDirection(GetWindowKeyboardLayout(testEdit.Hwnd), item[4]), item[1] ": real target HKL switched")
    }
    for mode in ["Full", "Majority"] {
        g_SwitchInputLanguageAfterConversion := false
        beforeHkl := GetWindowKeyboardLayout(testEdit.Hwnd)
        testEdit.Value := mode = "Full" ? "Ghbdtn" : "Привет мир Ghbdtn"
        testEdit.Focus()
        Send "^a"
        result := mode = "Full" ? ConvertSelectedFullHotkey() : ConvertSelectedMajorityHotkey()
        LiveIntegration_Assert(result && GetWindowKeyboardLayout(testEdit.Hwnd) = beforeHkl, mode ": disabled preserves HKL")
    }
    g_SwitchInputLanguageAfterConversion := true
    beforeHkl := GetWindowKeyboardLayout(testEdit.Hwnd)
    testEdit.Value := "Ghbdtn Привет"
    testEdit.Focus()
    Send "^a"
    LiveIntegration_Assert(ConvertSelectedFullHotkey() && testEdit.Value == "Привет Ghbdtn", "Full: mixed text is still converted")
    LiveIntegration_Assert(GetWindowKeyboardLayout(testEdit.Hwnd) = beforeHkl, "Full: ambiguous direction preserves HKL")

    otherEdit := testGui.AddEdit("w100")
    testEdit.Value := "Ghbdtn"
    testEdit.Focus()
    Send "^a"
    SetTimer((*) => otherEdit.Focus(), -60)
    LiveIntegration_Assert(!ConvertSelectedFullHotkey(), "Full: changed focus cancels replacement")
    LiveIntegration_Assert(testEdit.Value == "Ghbdtn" && otherEdit.Value = "", "Full: neither field is overwritten after focus change")
    LiveIntegration_Assert(GetWindowKeyboardLayout(testEdit.Hwnd) = beforeHkl, "Full: changed focus preserves HKL")
    FileAppend("PASS: real Full/Majority selection replacement and HKL, disabled setting, ambiguity and focus change`n", "*", "UTF-8")
}

LiveIntegration_FocusChange(testGui, testEdit) {
    global g_LiveBusy := true
    global g_LivePendingBuffer := ""
    global g_LiveRecoveryBuffer := ""
    global g_LiveContextInvalidated := false
    global g_LiveOperationWindow := testGui.Hwnd
    global g_LiveOperationFocus := testEdit.Hwnd
    global g_LiveBoundarySourcePrefix := ""
    global g_LiveBoundaryReplacementPrefix := ""
    global g_LiveTriggerMode := "DoubleSpace"
    global g_Buffer := "Ghbdtn  "
    otherEdit := testGui.AddEdit("w100")
    testEdit.Value := g_Buffer
    testEdit.Focus()
    Send "^{End}"
    SetLiveInputBuffering(true)
    SetTimer(LiveIntegration_MoveFocus.Bind(otherEdit), -25)
    TryLiveConvertDoubleSpace("Ghbdtn  ", testGui.Hwnd)
    Sleep 80
    LiveIntegration_Assert(otherEdit.Value = "", "queued text never enters another focused field")
    LiveIntegration_Assert(g_LiveRecoveryBuffer != "", "interrupted pending text remains recoverable")
    LiveIntegration_Assert(!g_LiveBusy, "focus change releases busy")
}

LiveIntegration_MoveFocus(otherEdit) {
    SendLevel 2
    SendEvent "{vk56}{vk42}{vk48}"
    Sleep 20
    otherEdit.Focus()
}

LiveIntegration_EndToEnd(testGui, testEdit, trigger) {
    global g_LiveTriggerMode := trigger
    global g_HotkeyLiveConvert := "#F9"
    global g_SwitchInputLanguageAfterConversion := true
    global g_LiveBusy, g_Buffer, ih
    DllCall("ActivateKeyboardLayout", "Ptr", FindInstalledKeyboardLayout("RU_TO_EN"), "UInt", 0, "Ptr")
    testEdit.Value := ""
    testEdit.Focus()
    ResetTypingBuffer()
    oldClipboard := ClipboardAll()
    A_Clipboard := "CLIPBOARD_SENTINEL"
    Hotkey("$*Space", LiveIntegration_Space, trigger = "DoubleSpace" ? "On I1" : "Off")
    Hotkey("$#F9", LiveIntegration_Hotkey, "On I1")
    try {
        SendLevel 2
        SetKeyDelay 15, 5
        SendEvent "Ghbdtn"
        Sleep 60
        LiveIntegration_Assert(g_Buffer = "Ghbdtn", "real keys: input tracked")
        if (trigger = "DoubleSpace") {
            SendEvent "{Space}"
            Sleep 60
            SendEvent "{Space}"
        } else
            SendEvent "#{F9}"
        Sleep 250
        expected := trigger = "DoubleSpace" ? "Привет " : "Привет"
        LiveIntegration_Assert(testEdit.Value = expected, trigger ": registered trigger; actual=" testEdit.Value)
        LiveIntegration_Assert(A_Clipboard = "CLIPBOARD_SENTINEL", "clipboard unchanged")
        LiveIntegration_Assert(!g_LiveBusy && ih.VisibleText, "input interception released")
    } finally {
        SendLevel 0
        Hotkey("$*Space", "Off")
        Hotkey("$#F9", "Off")
        A_Clipboard := oldClipboard
    }
}

LiveIntegration_Space(*) {
    SendLevel 0
    LiveSpacePressed()
}

LiveIntegration_Hotkey(*) {
    SendLevel 0
    LiveConvertHotkeyPressed()
}

LiveIntegration_RunFastTypingCase(testGui, testEdit, keys := "{vk56}{vk42}{vk48}", expectedPending := "мир", reverse := false) {
    global g_LiveBusy := true
    global g_LivePendingBuffer := ""
    global g_LiveContextInvalidated := false
    global g_LiveOperationWindow := testGui.Hwnd
    global g_LiveBoundarySourcePrefix := ""
    global g_LiveBoundaryReplacementPrefix := ""
    global g_LastWindow := testGui.Hwnd
    global g_Buffer := "Ghbdtn  "
    global g_LiveTriggerMode := "DoubleSpace"

    raw := reverse ? "руддщ  " : "Ghbdtn  "
    g_Buffer := raw
    DllCall("ActivateKeyboardLayout", "Ptr", FindInstalledKeyboardLayout(reverse ? "EN_TO_RU" : "RU_TO_EN"), "UInt", 0, "Ptr")

    testEdit.Value := raw
    testEdit.Focus()
    Send "^{End}"
    SetLiveInputBuffering(true)

    ; SendLevel 2 makes the synthetic test input behave like captured user input
    ; for an InputHook configured with I1.
    SetTimer(LiveIntegration_SendWhileBusy.Bind(keys), -25)
    result := TryLiveConvertDoubleSpace(raw, testGui.Hwnd)

    Sleep 100
    LiveIntegration_Assert(result, "fast typing: conversion succeeds")
    LiveIntegration_Assert(testEdit.Value = (reverse ? "hello " : "Привет ") expectedPending, "fast typing: buffered text follows converted fragment; actual=" testEdit.Value)
    LiveIntegration_Assert(g_Buffer = expectedPending, "fast typing: live buffer follows released text")
    LiveIntegration_Assert(!g_LiveBusy, "fast typing: busy flag released")
}

LiveIntegration_SendWhileBusy(text) {
    SendLevel 2
    SendEvent text
}

LiveIntegration_RunCase(testGui, testEdit, trigger, rawFragment, expectedText, expectedDirection) {
    global g_LiveBusy := true
    global g_LivePendingBuffer := ""
    global g_LiveContextInvalidated := false
    global g_LiveOperationWindow := testGui.Hwnd
    global g_LiveBoundarySourcePrefix := ""
    global g_LiveBoundaryReplacementPrefix := ""
    global g_LastWindow := testGui.Hwnd
    global g_Buffer := rawFragment
    global ih

    SetLiveInputBuffering(true)

    testEdit.Value := rawFragment
    testEdit.Focus()
    Send "^{End}"

    result := trigger = "Hotkey"
        ? TryLiveConvertHotkey(rawFragment, testGui.Hwnd)
        : TryLiveConvertDoubleSpace(rawFragment, testGui.Hwnd)

    Sleep 100
    LiveIntegration_Assert(result, trigger ": conversion succeeds")
    LiveIntegration_Assert(testEdit.Value = expectedText, trigger ": converted text remains intact; actual=" testEdit.Value "; expected=" expectedText)
    LiveIntegration_Assert(KeyboardLayoutMatchesDirection(GetWindowKeyboardLayout(testEdit.Hwnd), expectedDirection), trigger ": target input language changed")
    LiveIntegration_Assert(!g_LiveBusy, trigger ": busy flag released")
}
