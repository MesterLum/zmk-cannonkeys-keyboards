{
  description = "ZMK firmware development environment for CannonKeys keyboards";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Python with everything Zephyr / ZMK / west need at build time.
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          west
          pyelftools
          pyyaml
          pykwalify
          packaging
          progress
          psutil
          intelhex
          anytree
          gitpython
          colorama
          docutils
          ply
          natsort
          requests
          setuptools
          pip
          wheel
        ]);

        armToolchain = pkgs.gcc-arm-embedded;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            pythonEnv
            armToolchain
            pkgs.cmake
            pkgs.ninja
            pkgs.dtc
            pkgs.gperf
            pkgs.git
            pkgs.just
            pkgs.ccache
            pkgs.wget
            pkgs.unzip
            pkgs.coreutils
          ];

          shellHook = ''
            export ZEPHYR_TOOLCHAIN_VARIANT=gnuarmemb
            export GNUARMEMB_TOOLCHAIN_PATH=${armToolchain}

            # west / Zephyr cache locations kept inside the repo so they
            # follow the workspace and don't pollute $HOME.
            export ZEPHYR_BASE_HINT="$PWD/.build/zephyr"

            echo "ZMK dev shell ready."
            echo "  toolchain: gnuarmemb -> ${armToolchain}"
            echo "  python:    ${pythonEnv}/bin/python"
            echo "Run 'just' to see available commands."
          '';
        };
      });
}
