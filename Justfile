# zmx-flake task runner

# Default recipe
default:
    @just --list

# Format Nix files
fmt:
    nix fmt .

# Lint Nix files
lint:
    statix check .

# Format and lint
check: fmt lint
