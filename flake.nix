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

      shortRev = rev: builtins.substring 0 9 rev;
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

          # On macOS, zig 0.15 auto-detects the native macOS version (26+) and targets
          # arm64-macos in its linker searches. Modern macOS SDKs only ship arm64e-macos
          # TBD stubs, so zig's linker can't resolve symbols for arm64-macos targets.
          # The nixpkgs apple-sdk (14.4) still has arm64-macos stubs, so we point zig
          # at it by wrapping xcrun/xcode-select (which zig uses for SDK discovery) and
          # setting SDKROOT. The ghostty dependency also calls xcrun via apple_sdk.addPaths.
          darwinSdkAttrs = pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin (
            let
              sdkRoot = pkgs.apple-sdk.sdkroot;
              xcrunWrapper = pkgs.writeScriptBin "xcrun" ''
                #!/bin/sh
                echo "${sdkRoot}"
              '';
              xcodeselectWrapper = pkgs.writeScriptBin "xcode-select" ''
                #!/bin/sh
                echo "${sdkRoot}"
              '';
            in
            {
              glibc = null;
              musl = null;
              nativeBuildInputs = [
                xcrunWrapper
                xcodeselectWrapper
              ];
              SDKROOT = sdkRoot;
            }
          );

          mkZmx =
            src: packageAttrs:
            let
              unwrapped = env.package (
                {
                  inherit src;
                  zigBuildFlags = [ "-Doptimize=ReleaseSafe" ];
                  zigPreferMusl = pkgs.stdenv.hostPlatform.isLinux;
                }
                // darwinSdkAttrs
                // packageAttrs
              );
            in
            pkgs.runCommand unwrapped.name { nativeBuildInputs = [ pkgs.installShellFiles ]; } ''
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

          zmx = mkZmx zmx-src {
            zigBuildZonLock = ./build.zig.zon2json-lock-v0.5.0;
          };
          zmx-main = mkZmx zmx-src-main {
            pname = "zmx-main";
            version = shortRev zmx-src-main.rev;
            zigBuildZonLock = ./build.zig.zon2json-lock;
          };
        in
        {
          packages = {
            inherit zmx zmx-main;
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
      darwinModules.default = cacheModule;
      darwinModules.cache = cacheModule;
    };
}
