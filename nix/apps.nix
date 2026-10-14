{ ... }:
{
  perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      adapt = pkgs.writeShellApplication {
        name = "adapt";
        runtimeInputs = [
          config.packages.wine
          config.packages.winetricks
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.gawk
          pkgs.p7zip
          pkgs.util-linux
          pkgs.xdotool
          pkgs.xwininfo
          pkgs.imagemagick
          pkgs.grim
          pkgs.python3
          pkgs.wl-clipboard
        ];
        text = ''
          export ADAPT_DEPENDENCIES=${config.packages.windows-dependencies}
          export ADAPT_WPF_AERO2=${config.packages.wpf-aero2}/PresentationFramework.Aero2.dll
          export ADAPT_CLIPBOARD_SOURCE=${../compat/ClipboardRelay.cs}
          export ADAPT_CLIPBOARD_RELAY=${../scripts/clipboard-relay.py}
          export LD_LIBRARY_PATH=${pkgs.mesa}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
          export LIBGL_DRIVERS_PATH=${pkgs.mesa}/lib/dri
          export __EGL_VENDOR_LIBRARY_FILENAMES=${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json
          export __GLX_VENDOR_LIBRARY_NAME=mesa
        ''
        + builtins.readFile ../scripts/adapt.sh;
      };
    in
    {
      packages.default = adapt;
      checks.launcher = adapt;
      apps.default = {
        type = "app";
        program = lib.getExe adapt;
        meta.description = "Run the ADAPT desktop client";
      };
    };
}
