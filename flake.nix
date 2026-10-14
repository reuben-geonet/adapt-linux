{
  description = "ADAPT desktop client on Linux, with an isolated Wine environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      imports = [
        ./nix/runtime.nix
        ./nix/windows-dependencies.nix
        ./nix/apps.nix
        ./nix/devshell.nix
      ];
    };
}
