# Embedded by writeShellApplication, which supplies bash and strict mode.
# Credentials are entered only in the app. Never source .env in this launcher.
set -euo pipefail
umask 077
project="$(realpath "${ADAPT_PROJECT_DIR:-$PWD}")"
state="$(realpath -m "${ADAPT_STATE_DIR:-$project/.local}")"
cache="$(realpath -m "${ADAPT_CACHE_DIR:-$project/.cache}")"
version=2508.5.71
installer_hash=97f7d3ff4443d9268b56c526f1f47056c7cc23464226dcc7139bc8f6fc1b68e1
app_dir="$state/wine64/drive_c/ADAPT/$version"
app_exe="$app_dir/Adapt.Presentation.WPF.exe"
export WINEPREFIX="$state/wine64"
export WINEARCH=win64
export WINEDEBUG="${ADAPT_WINEDEBUG:--all,err+all}"
# Nix wraps wine in a shell script. Winetricks cannot infer WINE64 from it.
WINE="$(command -v wine)"
export WINE
export WINE64="$WINE"
WINESERVER="$(command -v wineserver)"
export WINESERVER
export W_CACHE="$cache/winetricks"
export WINEDLLOVERRIDES="winemenubuilder.exe=d${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"

fail() { printf '%s\n' "$*" >&2; exit 1; }

require_display() {
  [[ -n "${DISPLAY:-}" ]] || fail 'An X11/XWayland display is required. Start from your desktop session.'
}

configure_rendering() {
  wine reg add 'HKCU\Software\Wine\Drivers' /v Graphics /t REG_SZ /d x11 /f >/dev/null
  wine reg add 'HKCU\Software\Wine\AppDefaults\Adapt.Presentation.WPF.exe' \
    /v Version /t REG_SZ /d win10 /f >/dev/null
  wine reg add 'HKCU\Software\Microsoft\Avalon.Graphics' \
    /v DisableHWAcceleration /t REG_DWORD /d 1 /f >/dev/null
}

prepare_clipboard() {
  local source_hash source_win output_win
  source_hash="$(sha256sum "$ADAPT_CLIPBOARD_SOURCE")"
  if [[ -f "$state/wine64/drive_c/ADAPT/ClipboardRelay.exe" &&
        -f "$state/clipboard-source" &&
        "$(<"$state/clipboard-source")" == "$source_hash" ]]; then
    return
  fi
  source_win="$(winepath -w "$ADAPT_CLIPBOARD_SOURCE")"
  output_win='C:\ADAPT\ClipboardRelay.exe'
  mkdir -p "$state/wine64/drive_c/ADAPT"
  wine 'C:\windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' \
    /nologo /target:exe /reference:System.Windows.Forms.dll \
    "/out:$output_win" "${source_win%$'\r'}" >"$state/logs/clipboard-build.log" 2>&1 ||
    fail "Clipboard helper compilation failed. See $state/logs/clipboard-build.log."
  printf '%s\n' "$source_hash" >"$state/clipboard-source"
}

stop_clipboard() {
  if [[ -n "${clipboard_pid:-}" ]]; then
    kill "$clipboard_pid" 2>/dev/null || true
    wait "$clipboard_pid" 2>/dev/null || true
  fi
}

setup() {
  require_display
  local installer stage
  installer="$(realpath "${ADAPT_INSTALLER:-$project/adapt-installer.exe}")"
  [[ -f "$installer" ]] || fail "Place adapt-installer.exe in $project or set ADAPT_INSTALLER."
  printf '%s  %s\n' "$installer_hash" "$installer" | sha256sum --check --status ||
    fail 'Installer checksum differs from the pinned ADAPT 2508.5.71 installer.'
  mkdir -p "$state/logs" "$cache"
  chmod 700 "$state"
  exec 9>"$state/setup.lock"
  flock -n 9 || fail 'Another ADAPT setup is already running.'
  if [[ ! -f "$WINEPREFIX/system.reg" ]]; then
    printf 'Creating isolated Wine prefix: %s\n' "$WINEPREFIX"
    WINEDLLOVERRIDES='mscoree,mshtml=;winemenubuilder.exe=d' wineboot --init
    wineserver -w
  fi
  if [[ ! -f "$state/runtime-ready" ]]; then
    mkdir -p "$W_CACHE"
    cp -rL --no-preserve=mode "$ADAPT_DEPENDENCIES/." "$W_CACHE/"
    printf 'Installing Microsoft runtimes. Progress: %s\n' "$state/logs/setup.log"
    if ! winetricks -q dotnet48 d3dcompiler_47 vcrun2019 corefonts >"$state/logs/setup.log" 2>&1; then
      fail "Runtime installation failed. See $state/logs/setup.log; rerun setup after fixing the cause."
    fi
    winetricks -q win10 >>"$state/logs/setup.log" 2>&1
    touch "$state/runtime-ready"
  fi
  configure_rendering
  if [[ ! -f "$app_exe" ]]; then
    stage="$(mktemp -d "$cache/unpack.XXXXXX")"
    7z x -y -o"$stage/installer" "$installer" >"$state/logs/unpack.log"
    7z x -y -o"$stage/package" \
      "$stage/installer/Adapt_Platform_GNS_Production-$version-full.nupkg" \
      >>"$state/logs/unpack.log"
    mkdir -p "$(dirname "$app_dir")"
    mv "$stage/package/lib/net461" "$app_dir"
    rm -rf -- "$stage"
  fi
  install -m 600 "$ADAPT_WPF_AERO2" "$app_dir/PresentationFramework.Aero2.dll"
  prepare_clipboard
  printf 'ADAPT %s is prepared in %s\n' "$version" "$WINEPREFIX"
}

run() {
  require_display
  [[ -f "$state/runtime-ready" && -f "$app_exe" ]] || setup
  mkdir -p "$state/logs"
  chmod 700 "$state"
  exec 8>"$state/run.lock"
  flock -n 8 || fail 'ADAPT is already running in this prefix.'
  install -m 600 "$ADAPT_WPF_AERO2" "$app_dir/PresentationFramework.Aero2.dll"
  configure_rendering
  if [[ -n "${WAYLAND_DISPLAY:-}" && "${ADAPT_CLIPBOARD_RELAY_ENABLED:-1}" == 1 ]]; then
    prepare_clipboard
    python3 "$ADAPT_CLIPBOARD_RELAY" "$WINE" 'C:\ADAPT\ClipboardRelay.exe' \
      > /dev/null 2>"$state/logs/clipboard.log" &
    clipboard_pid=$!
    trap stop_clipboard EXIT
  fi
  local log
  log="$state/logs/run-$(date -u +%Y%m%dT%H%M%SZ).log"
  printf 'Starting ADAPT %s. Log: %s\n' "$version" "$log"
  cd "$app_dir"
  if [[ "${ADAPT_DESKTOP:-0}" == 0 ]]; then
    wine "$app_exe" "$@" 2>&1 | tee "$log"
  else
    wine explorer "/desktop=ADAPT,${ADAPT_DESKTOP:-1600x900}" "$app_exe" "$@" 2>&1 | tee "$log"
  fi
}

screenshot() {
  require_display
  local label="${1:-app}" window output geometry
  [[ "$label" =~ ^[a-zA-Z0-9_-]+$ ]] || fail 'Use letters, digits, hyphens, or underscores for the screenshot label.'
  window="$(xdotool search --onlyvisible --name '^Adapt Platform|^ADAPT - Wine desktop$' | tail -n 1 || true)"
  [[ -n "$window" ]] || fail 'The ADAPT application is not open.'
  output="$cache/screenshots/$(date -u +%Y%m%dT%H%M%SZ)-$label.png"
  mkdir -p "$cache/screenshots"
  geometry="$(xwininfo -id "$window" | awk '
    /Absolute upper-left X:/ { x=$4 }
    /Absolute upper-left Y:/ { y=$4 }
    /^[[:space:]]*Width:/ { w=$2 }
    /^[[:space:]]*Height:/ { h=$2 }
    END { printf "%s,%s %sx%s", x, y, w, h }
  ')"
  # Capture the compositor's actual presentation, including open menus.
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && grim -g "$geometry" "$output" 2>/dev/null; then
    :
  else
    magick import -window "$window" "$output"
  fi
  printf '%s\n' "$output"
}

case "${1:-run}" in
  setup) setup ;;
  run) if [[ $# -gt 0 ]]; then shift; fi; run "$@" ;;
  stop) wineserver -k ;;
  screenshot) shift; screenshot "$@" ;;
  wine) shift; wine "$@" ;;
  doctor)
    wine --version
    printf 'Project: %s\nPrefix: %s\nApplication: %s\nDisplay: %s\n' \
      "$project" "$WINEPREFIX" "$app_exe" "${DISPLAY:-unset}"
    if [[ -f "$state/runtime-ready" ]]; then
      wine reg query 'HKCU\Software\Microsoft\Avalon.Graphics' /v DisableHWAcceleration
      winetricks list-installed
    fi
    ;;
  help|--help|-h)
    printf '%s\n' 'Launch: nix run .' \
      'Optional troubleshooting: nix run . -- [doctor|stop|setup|screenshot LABEL|wine ARGS...]' \
      'Run from the project directory containing adapt-installer.exe.' \
      'ADAPT opens ordinary application windows. ADAPT_DESKTOP=1600x900 opts into a Wine desktop.'
    ;;
  *) fail "Unknown command: $1. Use adapt --help." ;;
esac
