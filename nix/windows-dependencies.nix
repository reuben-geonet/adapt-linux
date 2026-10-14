{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      downloads = map (
        download:
        download
        // {
          source = pkgs.fetchurl {
            inherit (download) url hash;
            name = builtins.baseNameOf download.path;
          };
        }
      ) (builtins.fromJSON (builtins.readFile ./windows-downloads.json));
      dotnet48 =
        (lib.findFirst (
          d: d.path == "dotnet48/ndp48-x86-x64-allos-enu.exe"
        ) (throw "The pinned .NET 4.8 download is missing") downloads).source;
    in
    {
      # Cache all Windows-side inputs in Nix too. Winetricks can then install
      # these exact bytes without relying on mutable vendor download redirects.
      packages.windows-dependencies = pkgs.linkFarm "adapt-windows-dependencies" (
        map (download: {
          name = download.path;
          path = download.source;
        }) downloads
      );
      # The Win7 MSI used by Winetricks omits this Windows 8+ inbox theme.
      # ADAPT's own ComboBox templates reference it explicitly. Extract the
      # matching Microsoft assembly from another payload in the SAME installer.
      packages.wpf-aero2 =
        pkgs.runCommand "adapt-wpf-aero2-4.8.3761"
          {
            nativeBuildInputs = [ pkgs.p7zip ];
          }
          ''
            7z e -y ${dotnet48} x64-Windows8.1-KB4486105-x64.cab > /dev/null
            mkdir -p "$out"
            7z e -y -o"$out" x64-Windows8.1-KB4486105-x64.cab \
              msil_presentationframework.aero2_31bf3856ad364e35_4.0.9696.16561_none_0135a2ef04afe2cd/presentationframework.aero2.dll > /dev/null
            mv "$out/presentationframework.aero2.dll" "$out/PresentationFramework.Aero2.dll"
            echo "fbaede1dd4513ce1dd4545ebc0876a7ee4449df92fd27099123124e8736bf8a4  $out/PresentationFramework.Aero2.dll" | sha256sum -c
          '';
    };
}
