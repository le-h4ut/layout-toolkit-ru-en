#Requires AutoHotkey v2.0

global g_AppName := "Layout Toolkit Test"

try {
    RunCapsLockFixTests()
    ExitApp(0)
} catch as err {
    FileAppend(err.Message "`n", "**", "UTF-8")
    ExitApp(1)
}

#Include ..\Modules\CapsLockFix.ahk

SplitByWhitespace(text) {
    parts := []
    pos := 1

    while pos := RegExMatch(text, "\s+|\S+", &match, pos) {
        parts.Push(match[0])
        pos += StrLen(match[0])
    }

    return parts
}

GetCanonicalExcludedToken(token) {
    global g_ExcludeWords

    trimChars := " `t`r`n'()[]{}<>.,;:!?" . Chr(34)
    cleaned := Trim(token, trimChars)
    key := StrLower(cleaned)

    if !g_ExcludeWords.Has(key) {
        return ""
    }

    startPos := InStr(token, cleaned)
    prefix := SubStr(token, 1, startPos - 1)
    suffix := SubStr(token, startPos + StrLen(cleaned))
    return prefix g_ExcludeWords[key] suffix
}

IsExcludedToken(token) {
    global g_ExcludeWords

    trimChars := " `t`r`n'()[]{}<>.,;:!?" . Chr(34)
    return g_ExcludeWords.Has(StrLower(Trim(token, trimChars)))
}

Notify(*) {
}

AssertEqual(expected, actual, label) {
    if (expected == actual) {
        return
    }

    throw Error(label ": expected '" expected "', got '" actual "'")
}

RunCapsLockFixTests() {
    global g_ExcludeWords

    g_ExcludeWords := Map(
        "powershell", "PowerShell",
        "github", "GitHub",
        "usb", "USB"
    )

    ; Проверка самого AssertEqual: различие регистра обязано провалить тест.
    rejectedCaseMismatch := false
    try AssertEqual("Core Jam", "cORE jAM", "case-sensitive assertion")
    catch {
        rejectedCaseMismatch := true
    }
    if !rejectedCaseMismatch {
        throw Error("AssertEqual ignored a case-only difference")
    }

    AssertEqual("Core Jam", FixCapsLockFullText("cORE jAM"), "reported full-mode regression")
    AssertEqual("Core jam", FixCapsLockText("cORE jAM"), "reported text in smart mode")

    AssertEqual(
        "Мама пошла в магазин и встретила там Александра с пакетом Oreo",
        FixCapsLockFullText("мАМА ПОШЛА В МАГАЗИН И ВСТРЕТИЛА ТАМ аЛЕКСАНДРА С ПАКЕТОМ oREO"),
        "mixed Russian and English case"
    )
    AssertEqual("привет мир", FixCapsLockFullText("ПРИВЕТ МИР"), "all-uppercase text")
    AssertEqual("Ёжик ёлка", FixCapsLockFullText("ёЖИК ЁЛКА"), "Cyrillic yo")
    AssertEqual("Hello, World!", FixCapsLockFullText("hELLO, wORLD!"), "punctuation")
    AssertEqual("PowerShell (GitHub). USB", FixCapsLockFullText("pOWERSHELL (gIThUB). usb"), "canonical exclusions")
    AssertEqual("Это пример", FixCapsLockText("эТО пРИМЕР"), "smart mode remains unchanged")
}
