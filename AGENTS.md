# Working on this project

Keep the user-facing workflow to `nix run .`. The README should explain only how
to launch the app. Keep maintenance knowledge here; do not add verification
reports, evidence folders, or progress notes. Preserve the modular flake-parts
structure and locked dependencies. Use Wine rather than a Windows VM.

## State and credentials

- The launcher defaults to the current directory. It expects the separately
  supplied `adapt-installer.exe` there; `ADAPT_PROJECT_DIR` overrides that root.
- The dedicated prefix is `.local/wine64`, with logs in `.local/logs` and caches
  in `.cache`. Use `ADAPT_STATE_DIR` and `ADAPT_CACHE_DIR` for isolated debugging.
  The launcher derives `WINEPREFIX` from its state directory; setting only
  `WINEPREFIX` externally does not select another prefix.
- Prefixes contain sign-in state. Never commit or share them. Do not source
  `.env`, print credentials, or put credentials or the installer in Nix inputs.
  Login happens inside the app. Microsoft SSO may need separate work; do not
  assume the non-SSO login path establishes SSO compatibility.
- Respect setup/run locks. Do not reset the user's prefix or kill other Wine
  sessions to troubleshoot. `stop` is scoped to this project's prefix.

## Installation traps

- ADAPT is a **64-bit .NET Framework/WPF** application despite the `net461`
  payload directory. Use native Microsoft .NET 4.8, not Wine Mono or modern .NET.
  The app also needs `d3dcompiler_47`, `vcrun2019`, and core fonts.
- Nix wraps `wine` in a shell script. Winetricks cannot infer `WINE64` correctly
  from that wrapper; explicitly exporting `WINE64="$WINE"` prevents architecture
  detection and empty `%AppData%` failures during setup.
- `wineboot --init` returns before prefix initialization finishes. Keep the
  subsequent `wineserver -w` before invoking Winetricks. Disabling `mscoree` and
  `mshtml` is only for prefix initialization, not normal application execution.
- Setup extracts the application's embedded Squirrel `.nupkg` and its
  `lib/net461` payload. It does not run the Squirrel updater. When changing the
  ADAPT version, update the installer hash, package filename, and versioned
  application directory together.
- Windows dependencies are fetched by Nix with fixed hashes, then copied into
  Winetricks' cache. Do not replace these with mutable runtime downloads.
  Microsoft's VS 2019 redirect changed the downloaded installer bytes: the
  Winetricks checksum overrides in `nix/runtime.nix` must agree with the pinned
  downloads in `nix/windows-downloads.json`. Revisit both on dependency upgrades.
- `.local/runtime-ready` skips runtime installation on later runs. Changing a
  dependency declaration alone will not reinstall it in an existing prefix.
  Prefer a separate state directory when investigating installation changes.

## WPF, graphics, and window sizing

- The misleading XAML error `Missing StartObject before StartMember ...
  Popup.Child` was caused by missing `PresentationFramework.Aero2`. ADAPT's
  ComboBox templates reference it explicitly, but the Windows 7 .NET MSI used
  by Winetricks omits this Windows inbox assembly. Switching Wine to Windows 7
  compatibility did not fix it; keep the application's Windows 10 setting.
- `nix/windows-dependencies.nix` extracts the matching genuine Aero2 DLL from
  the Windows 8.1 CAB inside the same pinned .NET 4.8 installer and checks its
  hash. Install it beside ADAPT. Do not patch the application executable or
  substitute an unrelated theme assembly to work around the XAML error.
- Keep WPF's `HKCU\Software\Microsoft\Avalon.Graphics\DisableHWAcceleration=1`.
  This addresses white WPF pages. ArcGIS still uses graphics libraries: the
  pinned Mesa library, DRI, EGL, and GLX settings prevent mixing Fedora/NVIDIA
  host drivers with Nix libraries. WPF software rendering does not make those
  Mesa settings redundant.
- Use the X11 Wine driver under Sway/XWayland. Native Wine Wayland was not a
  working replacement during debugging. Do not switch drivers casually.
- Default to ordinary application windows (`ADAPT_DESKTOP=0`). A fixed Wine
  desktop caused the smaller application surrounded by unused black space.
  `ADAPT_DESKTOP=1600x900` remains an optional diagnostic setting. Narrow window
  sizes can clip the application's form columns; that differs from white-page
  rendering failures.
- The embedded site map can label its basemap `Deprecated Basemap` and show
  coarse dark tiles even while the overview map and media images render.
  Investigate the basemap before treating that appearance as a WPF regression.
- Use `pkgs.xwininfo` and `pkgs.xorg-server`; the old `pkgs.xorg.*` attributes
  produce deprecation warnings.

## Clipboard: preserve the operation-based relay

- Wine's clipboard can work internally while Ctrl+C/Ctrl+X fail in native
  Wayland applications. Working right-click Copy and Ctrl+V do not establish
  that keyboard copies out of ADAPT work. Recopying identical text is essential
  to exercise this failure mode.
- The C# helper watches only Ctrl+C/Ctrl+X originating in ADAPT within its Wine
  session. It waits until key release and briefly retries delayed clipboard
  data or locks. Python materializes each operation through `wl-copy`.
- **Do not deduplicate by text or skip `wl-copy` when native text matches.**
  A repeated copy is a new operation; Wine's matching offer can subsequently
  disappear. Both shortcuts must reacquire the native clipboard even when the
  selected text is unchanged.
- Do not relay every clipboard sequence change. Importing native copies or
  the relay's own output can generate later Windows notifications, causing
  feedback or overwriting a newer Linux copy with stale text. Windows owner
  checks alone were insufficient, and XWayland ownership checks rejected real
  keyboard copies because Wine sometimes never claimed the X selection.
- Keep the relay scoped to explicit ADAPT shortcuts and its launcher lifetime.
  Preserve native Linux clipboard formats on unrelated copies. Text must stay
  in the private stdout pipe/stdin to `wl-copy`, never files, logs, or arguments.
- The helper is compiled with the prefix's .NET Framework64 `csc.exe` and cached
  against its source hash. Editing C# requires recompilation and a relay restart;
  avoid replacing its executable while it is running. On Wayland the launcher
  manages compilation, startup, and cleanup automatically.
- If automating the UI, refocus the actual ADAPT window before each operation
  and rediscover window IDs after restart. Under Sway, successful `xdotool` or
  `wtype` exit codes did not guarantee input reached the intended application.
  Do not save site edits or overwrite unrelated editor documents while debugging.

## Useful maintenance commands

These are optional troubleshooting tools; normal launch needs only `nix run .`.

| Command | Purpose |
| --- | --- |
| `nix run . -- doctor` | Wine version, prefix, rendering setting, installed runtimes |
| `nix run . -- stop` | Stop only this project's Wine session |
| `nix run . -- setup` | Run preparation without opening the application |
| `nix run . -- wine ARGS...` | Inspect registry/processes with this exact Wine and prefix |
| `nix run . -- screenshot LABEL` | Diagnostic capture under `.cache/screenshots/` |
| `nix develop` | Pinned development and UI diagnostic tools |
| `nix flake check` | Evaluate the flake and build the launcher, including ShellCheck |

Runtime details are in `.local/logs/setup.log`, `run-*.log`,
`clipboard-build.log`, and `clipboard.log`. These may contain application data;
keep them local. `ADAPT_WINEDEBUG` enables Wine diagnostics;
`ADAPT_CLIPBOARD_TRACE=1` logs only relay sequence/status metadata.
`ADAPT_CLIPBOARD_RELAY_ENABLED=0` disables the relay to isolate clipboard issues.
Environment changes take effect on the next launch. Documentation-only changes
do not require interrupting the running application or reinstalling runtimes.
