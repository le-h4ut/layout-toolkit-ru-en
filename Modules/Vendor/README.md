# Bundled dependencies

AHK sources and WebView2 loaders from [thqby/ahk2_lib](https://github.com/thqby/ahk2_lib), pinned to commit `559839b58353e31ec90796d1c2609c8f40b721f2`.

- WebView2/WebView2.ahk, ComVar.ahk, Promise.ahk, JSON.ahk: MIT; see LICENSE.
- WebView2Loader.dll (x86 and x64): Microsoft-signed WebView2 loader. Microsoft WebView2 distribution terms apply: https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.2903.40/License
- The Evergreen WebView2 Runtime is installed separately; it is not bundled.

No runtime downloads are performed by the web interfaces. Include this directory,
Assets/WebSettings and Assets/WebUnicodeInput in Windows packages.
