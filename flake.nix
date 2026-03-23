{
  description = "Nix flake for zmx - session persistence for terminal processes";

  inputs = {
    zig2nix.url = "github:Cloudef/zig2nix";
    zmx-src = {
      url = "github:neurosnap/zmx/v0.4.2";
      flake = false;
    };
  };

  outputs =
    { zig2nix, zmx-src, ... }:
    let
      inherit (zig2nix.inputs) flake-utils;
    in
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
      ]
      (
        system:
        let
          pkgs = import zig2nix.inputs.nixpkgs { inherit system; };
          env = zig2nix.outputs.zig-env.${system} {
            zig = zig2nix.outputs.packages.${system}.zig-0_15_2;
          };
          zmx = env.package {
            src = zmx-src;
            zigBuildFlags = [ "-Doptimize=ReleaseSafe" ];
            zigPreferMusl = true;
          };
        in
        {
          packages = {
            inherit zmx;
            default = zmx;
          };

          apps.default = {
            type = "app";
            program = "${zmx}/bin/zmx";
          };

          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              nixfmt
              statix
              just
            ];
          };

          formatter = pkgs.nixfmt;
        }
      );
}
