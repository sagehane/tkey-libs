# Heavily based on https://github.com/mitchellh/zig-overlay/blob/f29dc15782be8458374ca7b303ca1c156da37a67/templates/init/flake.nix

{
  description = "TKey device libs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, ... } @ inputs:
    let
      overlays = [
        (final: prev: {
          zigpkgs = inputs.zig.packages.${prev.system};
        })
      ];

      systems = builtins.attrNames inputs.zig.packages;
    in
    flake-utils.lib.eachSystem systems (
      system:
      let pkgs = import nixpkgs { inherit overlays system; }; in
      {
        devShells.default = pkgs.mkShellNoCC {
          nativeBuildInputs = with pkgs; [
            # Needed for Zig
            zigpkgs.master
          ] ++ (with llvmPackages_16; [
            # Needed for Make
            bintools-unwrapped
            clang-unwrapped
          ]);
        };
      }
    );
}
