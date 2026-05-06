# ZMK CannonKeys build automation.
#
# This repo is both a ZMK module (zephyr/module.yml) and a user-config repo
# (config/west.yml).  It cannot be the west topdir itself because west would
# try to clone Zephyr into ./zephyr/ and clash with the module metadata.
# So we keep the west workspace under .build/ and symlink config/ in.

set shell := ["bash", "-uc"]
set dotenv-load := true

repo        := justfile_directory()
workspace   := env_var_or_default("ZMK_WORKSPACE", repo / ".build")
config_link := workspace / "config"

# Default: list available recipes.
default:
    @just --list

# One-shot: create the workspace and pull all sources.
init: _ensure-workspace _west-init update

_ensure-workspace:
    mkdir -p "{{workspace}}"
    if [ ! -e "{{config_link}}" ]; then \
        ln -s "{{repo}}/config" "{{config_link}}"; \
    fi

_west-init:
    if [ ! -d "{{workspace}}/.west" ]; then \
        cd "{{workspace}}" && west init -l config; \
    else \
        echo "west already initialised at {{workspace}}"; \
    fi

# Pull / refresh Zephyr, ZMK and modules.
update:
    cd "{{workspace}}" && west update
    cd "{{workspace}}" && west zephyr-export

# Build a board.  Usage:
#   just build photon
#   just build photon studio-rpc-usb-uart studio
#
# Args:
#   BOARD     – e.g. photon, ck65_w, cerberus, link_left, link_right, ...
#   SNIPPET   – optional Zephyr snippet (e.g. studio-rpc-usb-uart)
#   VARIANT   – optional name suffix appended to the build dir / artifact,
#               useful for distinguishing studio builds etc.
build BOARD SNIPPET="" VARIANT="":
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{workspace}}"
    suffix=""
    [ -n "{{VARIANT}}" ] && suffix="_{{VARIANT}}"
    [ -z "{{VARIANT}}" ] && [ -n "{{SNIPPET}}" ] && suffix="_{{SNIPPET}}"
    build_dir="build/{{BOARD}}${suffix}"
    snippet_arg=""
    [ -n "{{SNIPPET}}" ] && snippet_arg="-S {{SNIPPET}}"
    extra_cmake=""
    [ -n "{{SNIPPET}}" ] && extra_cmake="-DCONFIG_ZMK_STUDIO=y"
    echo ">> west build -d $build_dir -b {{BOARD}} $snippet_arg"
    west build -d "$build_dir" -s zmk/app -b {{BOARD}} $snippet_arg -- \
        -DZMK_CONFIG="{{repo}}/config" \
        -DZMK_EXTRA_MODULES="{{repo}}" \
        $extra_cmake
    artifact=$(ls "$build_dir/zephyr/zmk."{uf2,bin,hex} 2>/dev/null | head -n1 || true)
    [ -n "$artifact" ] && echo "Artifact: {{workspace}}/$artifact"

# Build everything declared in build.yaml.
build-all:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{repo}}"
    python3 - <<'PY'
    import subprocess, sys, yaml, pathlib
    matrix = yaml.safe_load(pathlib.Path("build.yaml").read_text())
    entries = []
    for b in matrix.get("board", []) or []:
        entries.append({"board": b})
    entries.extend(matrix.get("include", []) or [])
    for e in entries:
        board = e["board"]
        snippet = e.get("snippet", "")
        variant = e.get("artifact-name", "")
        cmd = ["just", "build", board, snippet, variant]
        print(">>", " ".join(cmd))
        subprocess.run(cmd, check=True)
    PY

# Flash via west (works for boards with a configured runner).
flash BOARD VARIANT="":
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{workspace}}"
    suffix=""; [ -n "{{VARIANT}}" ] && suffix="_{{VARIANT}}"
    west flash -d "build/{{BOARD}}${suffix}"

# Copy the built .uf2 to a mounted bootloader volume.  Most ZMK boards in
# this repo are nice_nano-style and expose a USB MSC drive when in
# bootloader mode (double-tap reset).
#
#   just uf2 photon                          # auto-detects /Volumes/<NICENANO>
#   just uf2 photon "" /Volumes/MyBootloader # explicit mount
uf2 BOARD VARIANT="" MOUNT="":
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{workspace}}"
    suffix=""; [ -n "{{VARIANT}}" ] && suffix="_{{VARIANT}}"
    src="build/{{BOARD}}${suffix}/zephyr/zmk.uf2"
    if [ ! -f "$src" ]; then
        echo "no .uf2 at $src – run 'just build {{BOARD}}' first" >&2
        exit 1
    fi
    mount="{{MOUNT}}"
    if [ -z "$mount" ]; then
        mount=$(ls -d /Volumes/*BOOT* /Volumes/NICENANO* /Volumes/XIAO* 2>/dev/null | head -n1 || true)
    fi
    if [ -z "$mount" ] || [ ! -d "$mount" ]; then
        echo "no bootloader volume detected. Pass one explicitly:" >&2
        echo "  just uf2 {{BOARD}} '' /Volumes/<YOUR_DRIVE>" >&2
        exit 1
    fi
    echo "copying $src -> $mount/"
    cp "$src" "$mount/"
    sync

# Wipe build artifacts only.
clean:
    rm -rf "{{workspace}}/build"

# Wipe the entire workspace (zephyr, zmk, modules, .west, build).
nuke:
    rm -rf "{{workspace}}"

# Diagnostics.
doctor:
    #!/usr/bin/env bash
    set -u
    echo "repo:       {{repo}}"
    echo "workspace:  {{workspace}}"
    echo "west:       $(command -v west || echo MISSING)"
    echo "cmake:      $(command -v cmake || echo MISSING)"
    echo "ninja:      $(command -v ninja || echo MISSING)"
    echo "dtc:        $(command -v dtc || echo MISSING)"
    echo "arm-gcc:    $(command -v arm-none-eabi-gcc || echo MISSING)"
    echo "ZEPHYR_TOOLCHAIN_VARIANT=${ZEPHYR_TOOLCHAIN_VARIANT:-unset}"
    echo "GNUARMEMB_TOOLCHAIN_PATH=${GNUARMEMB_TOOLCHAIN_PATH:-unset}"
    if [ -d "{{workspace}}/.west" ]; then
        echo "west status:"
        (cd "{{workspace}}" && west list 2>&1 | sed 's/^/  /') || true
    else
        echo "workspace not initialised – run 'just init'"
    fi
