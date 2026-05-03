{
  description = "Nix flake for zmx - session persistence for terminal processes";

  inputs = {
    zig2nix.url = "github:Cloudef/zig2nix";
    zmx-src = {
      url = "github:neurosnap/zmx/v0.5.0";
      flake = false;
    };
    zmx-src-main = {
      url = "github:neurosnap/zmx";
      flake = false;
    };
  };

  outputs =
    {
      zig2nix,
      zmx-src,
      zmx-src-main,
      ...
    }:
    let
      inherit (zig2nix.inputs) flake-utils nixpkgs;

      cacheModule =
        { config, lib, ... }:
        {
          options.zmx-flake.cache.enable = lib.mkEnableOption "the zmx binary cache" // {
            default = true;
          };
          config = lib.mkIf config.zmx-flake.cache.enable {
            nix.settings = {
              substituters = [ "https://zmx.cachix.org" ];
              trusted-public-keys = [ "zmx.cachix.org-1:9E7zdDiSiG9PnSl8RFHbZ3AW2NmIy/7SPK9rRwed7r4=" ];
            };
          };
        };
    in
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ]
      (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          env = zig2nix.outputs.zig-env.${system} {
            zig = zig2nix.outputs.packages.${system}.zig-0_15_2;
          };

          mkZmx =
            src: packageAttrs:
            let
              unwrapped = env.package (
                {
                  inherit src;
                  zigBuildFlags = [ "-Doptimize=ReleaseSafe" ];
                  zigPreferMusl = true;
                }
                // packageAttrs
              );
            in
            pkgs.runCommand "zmx-${unwrapped.version}" { nativeBuildInputs = [ pkgs.installShellFiles ]; } ''
              mkdir -p $out/bin
              ln -s ${unwrapped}/bin/zmx $out/bin/zmx

              echo '#compdef zmx' > _zmx
              $out/bin/zmx completions zsh >> _zmx
              installShellCompletion --zsh _zmx

              $out/bin/zmx completions bash > zmx.bash
              installShellCompletion --bash zmx.bash

              $out/bin/zmx completions fish > zmx.fish
              installShellCompletion --fish zmx.fish
            '';

          mkZmxCross =
            src: packageAttrs: completionsFrom:
            let
              unwrapped = env.package (
                {
                  inherit src;
                  zigBuildFlags = [ "-Doptimize=ReleaseSafe" ];
                }
                // packageAttrs
              );
            in
            pkgs.runCommand "zmx-${unwrapped.version}" { nativeBuildInputs = [ pkgs.installShellFiles ]; } ''
              mkdir -p $out/bin
              ln -s ${unwrapped}/bin/zmx $out/bin/zmx

              echo '#compdef zmx' > _zmx
              ${completionsFrom}/bin/zmx completions zsh >> _zmx
              installShellCompletion --zsh _zmx

              ${completionsFrom}/bin/zmx completions bash > zmx.bash
              installShellCompletion --bash zmx.bash

              ${completionsFrom}/bin/zmx completions fish > zmx.fish
              installShellCompletion --fish zmx.fish
            '';

          zmx = mkZmx zmx-src {
            zigBuildZonLock = ./build.zig.zon2json-lock-v0.5.0;
          };
          zmx-main = mkZmx zmx-src-main {
            zigBuildZonLock = ./build.zig.zon2json-lock;
          };

          zmx-darwin-aarch64 = mkZmxCross zmx-src {
            zigBuildZonLock = ./build.zig.zon2json-lock-v0.5.0;
            zigTarget = "aarch64-macos";
          } zmx;
          zmx-darwin-x86_64 = mkZmxCross zmx-src {
            zigBuildZonLock = ./build.zig.zon2json-lock-v0.5.0;
            zigTarget = "x86_64-macos";
          } zmx;
          zmx-main-darwin-aarch64 = mkZmxCross zmx-src-main {
            zigBuildZonLock = ./build.zig.zon2json-lock;
            zigTarget = "aarch64-macos";
          } zmx-main;
          zmx-main-darwin-x86_64 = mkZmxCross zmx-src-main {
            zigBuildZonLock = ./build.zig.zon2json-lock;
            zigTarget = "x86_64-macos";
          } zmx-main;
        in
        {
          packages = {
            inherit
              zmx
              zmx-main
              zmx-darwin-aarch64
              zmx-darwin-x86_64
              zmx-main-darwin-aarch64
              zmx-main-darwin-x86_64
              ;
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
      )
    // {
      nixosModules.default = cacheModule;
      nixosModules.cache = cacheModule;
    };
}
