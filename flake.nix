{
  description = "Nix flake for zmx - session persistence for terminal processes";

  nixConfig = {
    allow-import-from-derivation = true;
  };

  inputs = {
    zig2nix.url = "github:Cloudef/zig2nix";
    zmx-src = {
      url = "github:neurosnap/zmx/v0.4.2";
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
            src:
            let
              deps = env.deriveLockFile "${src}/build.zig.zon2json-lock" {
                inherit (env) zig;
                name = "zmx-dependencies";
              };
              patchedDeps =
                if pkgs.stdenv.hostPlatform.isDarwin then
                  pkgs.runCommand "zmx-dependencies-patched" { nativeBuildInputs = [ pkgs.python3 ]; } ''
                    mkdir -p $out
                    cp -RL ${deps}/. $out/
                    chmod -R +w $out

                    python3 <<'PY'
                    import os
                    from pathlib import Path

                    build_zig = next(Path(os.environ["out"]).glob("ghostty-*/build.zig"))
                    data = build_zig.read_text()

                    data = data.replace(
                        """    // macOS only artifacts. These will error if they're initialized for\n    // other targets.\n    if (config.target.result.os.tag.isDarwin()) {\n""",
                        """    // macOS only artifacts. These are only needed when producing the\n    // Darwin library/app artifacts themselves.\n    if (config.target.result.os.tag.isDarwin() and (config.emit_xcframework or config.emit_macos_app)) {\n""",
                    )
                    data = data.replace(
                        """        // On macOS we can run the macOS app. For \"run\" we always force\n        // a native-only build so that we can run as quickly as possible.\n        if (config.target.result.os.tag.isDarwin()) {\n""",
                        """        // On macOS we can run the macOS app. For \"run\" we always force\n        // a native-only build so that we can run as quickly as possible.\n        if (config.target.result.os.tag.isDarwin() and (config.emit_xcframework or config.emit_macos_app)) {\n""",
                    )

                    build_zig.write_text(data)
                    PY
                  ''
                else
                  null;

              unwrapped = env.package {
                inherit src;
                zigBuildFlags = [ "-Doptimize=ReleaseSafe" ];
                zigPreferMusl = pkgs.stdenv.hostPlatform.isLinux;
                nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
                  pkgs.xcbuild
                  pkgs.python3
                ];
                buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
                  pkgs.apple-sdk
                ];
                postPatch = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
python3 <<'PY'
from pathlib import Path

p = Path('build.zig')
data = p.read_text()
data = data.replace(
    '''    if (b.lazyDependency("ghostty", .{
        .target = target,
        .optimize = optimize,
    })) |dep| {
''',
    '''    if (b.lazyDependency("ghostty", .{
        .target = target,
        .optimize = optimize,
        .@"emit-xcframework" = false,
        .@"emit-macos-app" = false,
    })) |dep| {
''',
    1,
)
data = data.replace(
    '''        if (b.lazyDependency("ghostty", .{
            .target = resolved,
            .optimize = .ReleaseSafe,
        })) |dep| {
''',
    '''        if (b.lazyDependency("ghostty", .{
            .target = resolved,
            .optimize = .ReleaseSafe,
            .@"emit-xcframework" = false,
            .@"emit-macos-app" = false,
        })) |dep| {
''',
    1,
)
p.write_text(data)
PY
                '';
                preBuild = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
                  rm -f "$ZIG_GLOBAL_CACHE_DIR"/p
                  ln -s ${patchedDeps} "$ZIG_GLOBAL_CACHE_DIR"/p
                '';
              };
            in
            pkgs.runCommand "zmx-${unwrapped.version}" { nativeBuildInputs = [ pkgs.installShellFiles ]; }
              ''
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

          zmx = mkZmx zmx-src;
          zmx-main = mkZmx zmx-src-main;
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
    };
}
