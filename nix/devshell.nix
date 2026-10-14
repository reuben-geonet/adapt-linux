{ ... }:
{
  perSystem = { config, pkgs, ... }: {
    devShells.default = pkgs.mkShell {
      packages = [
        config.packages.default
        config.packages.wine
        config.packages.winetricks
        pkgs.p7zip
        pkgs.cabextract
        pkgs.xdotool
        pkgs.wtype
        pkgs.xwininfo
        pkgs.xorg-server
        pkgs.imagemagick
        pkgs.grim
        pkgs.shellcheck
        pkgs.nixfmt
        pkgs.python3
      ];
    };
    formatter = pkgs.nixfmt;
  };
}
