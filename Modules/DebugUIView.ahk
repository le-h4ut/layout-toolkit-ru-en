; A copy-local debug override. Missing or invalid file means the normal WebView2 UI.
LTDebugUI_IsNative() {
    path := A_ScriptDir "\Assets\DebugUIView.mode"
    if !FileExist(path)
        return false
    try {
        return StrLower(Trim(FileRead(path, "UTF-8"), " `t`r`n")) = "native"
    } catch {
        return false
    }
}

LTDebugUI_PrewarmUnicode(*) {
    if !LTDebugUI_IsNative()
        LTWebUnicodeInput.Prewarm()
}
