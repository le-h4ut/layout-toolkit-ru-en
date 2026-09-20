# Layout Toolkit RU-EN

A small Windows utility for fixing text typed in the wrong RU/EN keyboard layout.

Небольшая утилита для Windows, которая помогает исправлять текст, набранный в неправильной RU/EN-раскладке.

Powered by **AutoHotkey v2**.

---

## Features / Возможности

- Fix selected text typed in the wrong RU/EN layout.
- Majority mode for mixed RU/EN text.
- Live mode: fix the current typed fragment with double space or an alternative hotkey.
- Unicode Input: insert Unicode characters by HEX code.
- CapsLock Full Fix: invert the case of every RU/EN letter.
- CapsLock Fix: normalize accidental CapsLock case with smart analysis.
- Settings GUI with hotkeys, exclusions and live-mode settings.
- Local web settings with light and dark themes hosted in WebView2 (development version).
- User files stored in `Documents\Layout Toolkit`.

---

## Web settings / Веб-настройки

The Git version uses a local HTML/CSS/JavaScript settings window hosted in
Microsoft Edge WebView2. This is not a website: no HTTP server or internet connection
is needed for the interface. AutoHotkey still handles conversion and Windows input.
The settings window and Unicode Input use the web UI. Training and confirmation
dialogs remain native for now.

The appearance switch in the settings header changes both web windows. The selected
theme is stored in the `[Appearance]` section of `settings.ini` and is reused after
restart. The native Windows title bars follow the same theme through DWM and update
without recreating either window; early Windows 10 builds use the legacy attribute
fallback.

Unicode Input keeps the existing HEX parser, insertion engine, recent symbols,
automatic favorites and configurable `1…5` shortcuts. The new window places
favorites and history side by side and adapts from 650×500 down to 560×400.
Its WebView is prepared in the background shortly after Toolkit starts and stays
hidden after use, so repeated openings do not recreate the browser runtime.

Light and dark themes are available from the switch in the settings header. Open the
window from the tray's settings item.
Live, Unicode and hotkey edits are applied with **Save**; navigating away from a
changed section prompts to save or discard the draft. Closing the window hides it
and keeps the draft until the application exits.

Requires the **Microsoft Edge WebView2 Runtime**. If it cannot initialize, the old
settings window opens with an explanation. No runtime is installed automatically.
The WebView2 profile is stored under `%LocalAppData%\Layout Toolkit\WebView2`;
application settings remain in `Documents\Layout Toolkit`.

When packaging Windows builds, include `Assets\WebSettings`, `Assets\WebUnicodeInput`
and `Modules\Vendor`
in addition to the existing runtime files. Dependency licenses are documented in
`Modules\Vendor\README.md`. Do not include `Tests` or Linux files in Windows ZIPs.

Developer checks, with AutoHotkey v2 installed:

```powershell
.\Tests\Run-WebSettingsTests.ps1
.\Tests\Run-WebSettingsTests.ps1 -BrowserTests
.\Tests\Run-WebSettingsTests.ps1 -UnicodeBrowserTests
.\Tests\Run-WebSettingsTests.ps1 -PrewarmTests
.\Tests\Run-WebSettingsTests.ps1 -Preview
.\Tests\Run-WebSettingsTests.ps1 -UnicodePreview
```

These create an isolated temporary copy with separate settings and WebView2 data.
Global hotkey registration is replaced by test doubles. `-BrowserTests` exercises
the real web/native message bridge and saves rendering snapshots in that temporary
directory. The Unicode variants do the same for Unicode Input. Preview switches keep
the test window running; stop the reported PID after use.
It does not modify the working installation or the real user profile.

---

## Super Quick Install and Start / Очень Быстрая Установка и Запуск

Open PowerShell and paste this command:

```powershell
irm https://raw.githubusercontent.com/le-h4ut/layout-toolkit-ru-en/main/install.ps1 | iex
```

The installer asks where to place Layout Toolkit, verifies the release archive and
starts the application. Running the same command again updates the detected
installation. Installation information is stored in
`%LocalAppData%\Layout Toolkit\install.json`.

---

## Quick start / Быстрый запуск

1. Download and extract the project or release archive. For the Windows release, open the extracted `Layout Toolkir Ru En` folder.
2. Run:

```text
Run_Layout_Toolkit.cmd
```

The launcher recognizes standard, custom and portable AutoHotkey v2 installations.

If AutoHotkey v2 is not found, it explains why AHK is required and lets you either:

* download the latest stable version from the official website and install it for the current user;
* select an existing `AutoHotkey.exe` manually;
* cancel the launch.

The selected executable is remembered in `%LocalAppData%\Layout Toolkit\autohotkey-path.txt`.

---

## Default hotkeys / Хоткеи по умолчанию

| Action                     | Hotkey              |
| -------------------------- | ------------------- |
| Full layout conversion     | `Win + F12`         |
| Majority layout conversion | `Win + F11`         |
| Toggle live mode           | `Win + F10`         |
| Convert current live text  | `Win + F9`          |
| Unicode Input              | `Ctrl + Shift + U`  |
| Smart CapsLock Fix         | `Win + Shift + F11` |
| CapsLock Full Fix          | `Win + Shift + F12` |

Hotkeys can be changed in:

```text
Documents\Layout Toolkit\hotkeys.ini
```

The built-in hotkeys can also be captured and changed directly in the Settings GUI.

---

## How it works / Как это работает

### Layout Fix

Use this when selected text was typed in the wrong layout. The conversion direction is detected separately for each whitespace-delimited token, so RU and EN fragments can be fixed in one pass. Every character of an unambiguous RU or EN token is converted by its physical keyboard key, including punctuation. Words from the exclusions dictionary are not changed.

```text
Ghbdtn/ Rfr ltkf&
```

becomes:

```text
Привет. Как дела?
```

### Majority mode

Useful for mixed text where only some fragments are in the wrong layout.

```text
Ghbdtn/ Я уже дома. Rfr дела?
```

becomes:

```text
Привет. Я уже дома. Как дела?
```

### Live mode

Live mode fixes the current typed fragment using one of two alternative triggers. Double space is selected by default and leaves one trailing space after conversion. The live hotkey (`Win + F9` by default) performs the same conversion without adding anything at the end.

```text
Z gbie ntrcn/  
```

becomes:

```text
Я пишу текст. 
```

Live mode sends synthetic `Backspace` and paste actions, so it is best for messengers, search fields and short input fields.

For long documents, use selected-text conversion instead.

### Unicode Input

Input Unicode characters by HEX code:

```text
2014
```

inserts:

```text
—
```

Multiple codes are supported:

```text
0060 2014 0060
```

inserts:

```text
`—`
```

The Settings GUI can open Unicode Input in clipboard mode.

History and favorites use `Ctrl + 1…5` and `Shift + 1…5` by default. Their prefix keys can be changed to `Ctrl`, `Shift`, `Alt`, `Win` or `Tab` in either Unicode Input or the Settings GUI. When `Tab` is selected, normal Tab navigation is disabled inside Unicode Input.

### CapsLock Fix

CapsLock Full Fix inverts every Russian and English letter without guessing:

```text
мАМА ПОШЛА В МАГАЗИН
```

becomes:

```text
Мама пошла в магазин
```

The smart CapsLock Fix remains available for normalizing text such as `эТО пРИМЕР` to `Это пример`.

```text
pOWERSHELL
```

can become:

```text
PowerShell
```

if `PowerShell` is listed in `exclude.txt`. Canonical spelling from the exclusions dictionary has priority in both modes.

---

## User files / Пользовательские файлы

Layout Toolkit stores user data here:

```text
Documents\Layout Toolkit
```

Main files:

```text
settings.ini
hotkeys.ini
exclude.txt
```

* `settings.ini` — user settings.
* `hotkeys.ini` — user hotkeys.
* `exclude.txt` — exclusions and canonical spelling.

`exclude.txt` is useful for technical words, commands, paths, links and names like:

```text
PowerShell
GitHub
USB
https://
C:\
```

---

## Settings GUI

The Settings GUI can:

* capture and change built-in hotkeys;
* open and reload `hotkeys.ini`;
* reset hotkeys to defaults;
* open and reload `exclude.txt`;
* reset exclusions to defaults;
* choose between double-space and hotkey live triggers;
* configure live mode;
* configure synchronized Unicode Input history and favorites shortcuts;
* open Unicode Input in clipboard mode.

Open it from the tray menu or by double-clicking the Layout Toolkit tray icon.

---

## Startup / Автозапуск

Run:

```text
Startup_Manager.cmd
```

It can add or remove Layout Toolkit from Windows startup.

The startup shortcut uses the same AutoHotkey resolver as the normal launcher, including custom and portable installations.

---

## Requirements / Требования

* Windows 10 or Windows 11
* AutoHotkey v2

---

## Known limitations / Ограничения

* Live mode is intended mostly for short messages.
* Some applications may handle synthetic `Backspace` / paste differently.
* For long documents, selected-text conversion is safer than live mode.

---

## Changelog

See:

```text
CHANGELOG.md
```
