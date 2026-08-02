{
  description = "Nix flake for zmx - session persistence for terminal processes";

  inputs = {
    zig2nix.url = "github:Cloudef/zig2nix";
    zmx-src = {
      url = "github:neurosnap/zmx/v0.7.0";
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
          zigVersion =
            src:
            let
              zon = builtins.replaceStrings [ "\n" ] [ " " ] (builtins.readFile "${src}/build.zig.zon");
              match = builtins.match ".*\\.minimum_zig_version = \"([^\"]+)\".*" zon;
            in
            if match == null then
              throw "Could not determine minimum_zig_version from ${src}/build.zig.zon"
            else
              builtins.head match;

          envFor =
            src:
            let
              zigAttr = "zig-${builtins.replaceStrings [ "." ] [ "_" ] (zigVersion src)}";
            in
            zig2nix.outputs.zig-env.${system} {
              zig = zig2nix.outputs.packages.${system}.${zigAttr};
            };

          # On macOS, Zig auto-detects the native macOS version (26+) and targets
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
                pkgs.python3
                xcrunWrapper
                xcodeselectWrapper
              ];
              SDKROOT = sdkRoot;
              zigTarget =
                if pkgs.stdenv.hostPlatform.isAarch64 then "aarch64-macos.13.0" else "x86_64-macos.13.0";
              postPatch = ''
                python3 - <<'PY'
                from pathlib import Path

                path = Path("build.zig")
                text = path.read_text()
                text = text.replace(
                    "        exe.linkLibC();",
                    "        if (target.result.os.tag == .macos) exe.use_lld = false;\n        exe.linkLibC();",
                    1,
                )
                text = text.replace(
                    "        exe_check.linkLibC();",
                    "        if (target.result.os.tag == .macos) exe_check.use_lld = false;\n        exe_check.linkLibC();",
                    1,
                )
                text = text.replace(
                    "            release_exe.linkLibC();",
                    "            if (resolved.result.os.tag == .macos) release_exe.use_lld = false;\n            release_exe.linkLibC();",
                    1,
                )
                path.write_text(text)

                replacements = {
                    "std.Io.File.Permissions.fromMode(cfg.log_mode)":
                        "std.Io.File.Permissions.fromMode(@intCast(cfg.log_mode))",
                    "std.Io.File.Permissions.fromMode(self.cfg.log_mode)":
                        "std.Io.File.Permissions.fromMode(@intCast(self.cfg.log_mode))",
                    "fn wakeSignalPipe(_: std.os.linux.SIG,":
                        "fn wakeSignalPipe(_: lib_posix.SIG,",
                }
                for path in Path("src").rglob("*.zig"):
                    text = path.read_text()
                    patched = text
                    for old, new in replacements.items():
                        patched = patched.replace(old, new)
                    if patched != text:
                        path.write_text(patched)
                PY
              '';
            }
          );

          mkZmx =
            src: zigBuildZonLock: packageAttrs:
            let
              env = envFor src;
              unwrapped = env.package (
                {
                  inherit src zigBuildZonLock;
                  zigBuildFlags = [ "-Doptimize=ReleaseSafe" ];
                  zigPreferMusl = pkgs.stdenv.hostPlatform.isLinux;
                  preBuild =
                    pkgs.lib.optionalString (pkgs.stdenv.isLinux && pkgs.lib.versionAtLeast env.zig.version "0.16")
                      ''
                        # Zig 0.16's build runner cannot execute zig2nix's Linux shell wrapper.
                        export PATH="${env.zig}/bin:$PATH"
                      '';
                }
                // darwinSdkAttrs
                // packageAttrs
              );
            in
            pkgs.runCommand unwrapped.name
              {
                nativeBuildInputs = [ pkgs.installShellFiles ];
                meta.mainProgram = "zmx";
              }
              ''
                mkdir -p $out/bin
                ln -s ${unwrapped}/bin/zmx $out/bin/zmx

                export ZMX_DIR="$TMPDIR/zmx"

                echo '#compdef zmx' > _zmx
                $out/bin/zmx completions zsh >> _zmx
                installShellCompletion --zsh _zmx

                $out/bin/zmx completions bash > zmx.bash
                installShellCompletion --bash zmx.bash

                $out/bin/zmx completions fish > zmx.fish
                installShellCompletion --fish zmx.fish
              '';

          zmx = mkZmx zmx-src ./locks/zmx-release.zon2json-lock { };
          zmx-main = mkZmx zmx-src-main ./locks/zmx-main.zon2json-lock {
            pname = "zmx-main";
            version = shortRev zmx-src-main.rev;
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
