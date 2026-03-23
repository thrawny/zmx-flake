# zmx-flake

Nix flake for [zmx](https://github.com/neurosnap/zmx) — session persistence for terminal processes.

This is a community-maintained flake that builds zmx from source using [zig2nix](https://github.com/Cloudef/zig2nix). It exists because the upstream Nix packaging in nixpkgs is blocked by a [Zig compiler bug](https://codeberg.org/ziglang/zig/issues/30191).

## Usage

Run directly:

```sh
nix run github:thrawny/zmx-flake
```

Add as a flake input:

```nix
{
  inputs.zmx-flake.url = "github:thrawny/zmx-flake";

  outputs = { zmx-flake, ... }: {
    # zmx-flake.packages.${system}.zmx
  };
}
```

## Supported platforms

- `x86_64-linux`
- `aarch64-linux`
