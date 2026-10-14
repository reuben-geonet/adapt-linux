{ ... }:
{
  perSystem = { pkgs, ... }: {
    # Keep Wine, its helper programs, and the development shell on one version.
    packages.wine = pkgs.wineWow64Packages.stableFull;
    # Microsoft's VS 2019 redirect now serves these newer signed installers.
    # The complete downloads are also pinned by hash in windows-downloads.json.
    packages.winetricks = pkgs.winetricks.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace src/winetricks \
          --replace-fail 49545cb0f6499c4a65e1e8d5033441eeeb4edfae465a68489a70832c6a4f6399 38c9437e6e9ef1db2671b3f0c879febec08521bd2c23231199f626b69ae1c65e \
          --replace-fail 5d9999036f2b3a930f83b7fe3e2186b12e79ae7c007d538f52e3582e986a37c3 6afae68a783f11292149175844aed0e2ce3f247bc0250f6cb18c931295b3f399
      '';
    });
  };
}
