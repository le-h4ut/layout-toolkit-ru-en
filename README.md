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
- Local web settings with light and dark themes hosted in WebView2.
- User files stored in `Documents\Layout Toolkit`.

---

## Web settings / Веб-настройки

Version 1.5.0 uses a local HTML/CSS/JavaScript settings window hosted in
Microsoft Edge WebView2. This is not a website: no HTTP server or internet connection
is needed for the interface. AutoHotkey still handles conversion and Windows input.
The settings window, Unicode Input and quick-start guide use the web UI.
Confirmation dialogs remain native for now.

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
changed section prompts to save or discard the draft. Opening settings shows a
small loading window until the web UI is ready. Closing settings releases its
WebView2 controller and discards unsaved drafts; the next opening loads it again.

Requires the **Microsoft Edge WebView2 Runtime**. If it cannot initialize, the old
settings window opens with an explanation. No runtime is installed automatically.
The WebView2 profile is stored under `%LocalAppData%\Layout Toolkit\WebView2`;
application settings remain in `Documents\Layout Toolkit`.

When packaging Windows builds, include `Assets\WebSettings`, `Assets\WebUnicodeInput`,
`Assets\WebWelcome` and `Modules\Vendor`
in addition to the existing runtime files. Dependency licenses are documented in
`Modules\Vendor\README.md`. Do not include `Tests`, `Design` or Linux files in Windows ZIPs.

Developer checks, with AutoHotkey v2 installed:

```powershell
.\Tests\Run-WebSettingsTests.ps1
.\Tests\Run-WebSettingsTests.ps1 -BrowserTests
.\Tests\Run-WebSettingsTests.ps1 -SettingsLifecycleTests
.\Tests\Run-WebSettingsTests.ps1 -WelcomeBrowserTests
.\Tests\Run-WebSettingsTests.ps1 -UnicodeBrowserTests
.\Tests\Run-WebSettingsTests.ps1 -PrewarmTests
.\Tests\Install.Tests.ps1
.\Tests\Install.Transaction.Tests.ps1
.\Tests\Install.Process.Tests.ps1
.\Tests\HealthCheck.Tests.ps1
.\Tests\Run-LiveInputLanguageTests.ps1
.\Tests\Run-LiveInputLanguageTests.ps1 -RealInput
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
(irm https://raw.githubusercontent.com/le-h4ut/layout-toolkit-ru-en/main/install.ps1).TrimStart([char]0xFEFF) | iex
```

The installer asks where to place Layout Toolkit, verifies the release archive and
starts the application. Running the same command again updates the detected
installation. Installation information is stored in
`%LocalAppData%\Layout Toolkit\install.json`.

**Updating v1.5.0 or an earlier beta:** the old in-app updater starts its local
installer from inside the installation directory, which can block backup moves.
Close Toolkit and run the fresh installer once. For a manually extracted copy,
pass its existing folder explicitly (replace the example path):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/le-h4ut/layout-toolkit-ru-en/main/install.ps1).TrimStart([char]0xFEFF))) -Update -InstallPath 'D:\Scripts\LT My' -NoAutostart
```

`-NoAutostart` keeps startup disabled; omit it if you want startup enabled.
Existing managed preferences are retained. After v1.5.1 is installed, subsequent
updates can use the Settings button. Installer logs are kept in
`%LocalAppData%\Layout Toolkit\Logs`; UI failures show a persistent error dialog.

The commands strip the leading UTF-8 BOM before evaluating downloaded text.
Windows PowerShell 5.1 otherwise fails to recognize the installer's parameter
block. The BOM is retained in the file for correct Cyrillic decoding with `-File`.

---

## Quick start / Быстрый запуск

1. Download and extract the project or release archive. For the Windows release, open the extracted `Layout Toolkit Ru En` folder.
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

The **Installation / Установка** settings page shows the current program folder,
manages this copy's startup shortcut and checks for updates. In-app updates work
for managed and manually extracted copies when `install.ps1` and the launcher
are present. The first successful update registers the current folder in
`install.json`; Git checkouts remain protected from in-app replacement.
Windows release archives must include
both `install.ps1` and `Manage_Startup.ps1` with the other Windows files.

Safe updates verify the ZIP's size and SHA-256 against `latest.json`, then run
`--health-check` before replacing any installed files. The probe checks required
assets and core conversion/Unicode/JSON routines without initializing the user
profile, hotkeys or WebView2. The installer refuses older archives which do not
support this protocol; published beta archives remain unchanged.

The replacement is staged on the destination drive, including when Windows TEMP
is on a different drive. The old directory remains as a backup until the new
process confirms initialization and hotkey registration. Failed startup or state/
shortcut writes restore the old directory and exact installation metadata.
If rollback itself fails, recovery files are retained and their paths are reported.
An update started from settings waits for the previous process to exit and restarts
the old copy after a recoverable failure. For a manual update, close Toolkit first.
This is a startup check, not a guarantee against a later application crash.

Developer probe (AutoHotkey v2; no running copy is replaced):

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /force /ErrorStdOut=UTF-8 .\Layout_Toolkit_RU_EN.ahk --health-check
```

Success prints `LAYOUT_TOOLKIT_HEALTH_OK` and returns exit code 0. To exercise
cross-drive replacement, run `Tests\Install.Transaction.Tests.ps1 -TargetRoot`
with a directory on another drive. Tests use disposable fixtures, not the real
installation or startup folder.

For UI comparison in a source checkout, run `Assets\DebugUIView.ps1` from
PowerShell with `-Mode Native` or `-Mode Web` (or omit `-Mode` for a menu).
Close and reopen the settings or Unicode Input window to apply the choice;
the running app does not need a restart. The copy-local debug marker is ignored
by Git, and WebView2 remains the default when no marker exists.

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

Live replaces text using Unicode keyboard input and leaves the clipboard unchanged.
Paragraph breaks, tabs, and alphabet changes between words limit the current fragment.
Typing during replacement is queued. If focus changes before queued text is released,
use **Копировать отложенный ввод** in the tray menu to recover it explicitly.

```text
Z gbie ntrcn/  
```

becomes:

```text
Я пишу текст. 
```

Live mode sends synthetic `Backspace` and Unicode text input, so it is best for messengers, search fields and short input fields.

For long documents, use selected-text conversion instead.

### Automatic input-language switching

In **Обзор**, enable **Переключать раскладку после исправления** to apply the
same optional behavior to Live, Full and Majority. It is off by default;
the preference from the older Live-only setting is preserved automatically.

After replacement, EN → RU requests an installed Russian layout, and RU → EN
requests an installed English layout (not necessarily US English). Full only
switches when the changed letters have one conversion direction; preserved
exceptions do not determine that direction. Majority follows its target language.
Unchanged text and ambiguous Full conversions do not switch the input language.
If the target window or focused field changes, no request is sent to another field.
Some applications may ignore Windows input-language requests; this does not undo
the completed conversion.

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
