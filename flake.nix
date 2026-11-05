{
  description = "Waddly, a desktop pet that reacts to keyboard input";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      # GitHub Releases publish an Apple Silicon DMG only.
      packageSystems = [ "aarch64-darwin" ];
      # Linux systems run the formatter and the module evaluation in CI.
      checkSystems = packageSystems ++ [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forSystems = systems: f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      nixSrc = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [
          ./flake.nix
          ./nix
        ];
      };
      moduleSmoke = import ./nix/checks.nix {
        inherit lib;
        pkgsBySystem = nixpkgs.legacyPackages;
      };
      formatterFor =
        pkgs:
        pkgs.writeShellScriptBin "waddly-nixfmt" ''
          set -euo pipefail
          mapfile -t files < <(find flake.nix nix -name '*.nix' | sort)
          exec ${lib.getExe pkgs.nixfmt} "$@" "''${files[@]}"
        '';
    in
    {
      packages = forSystems packageSystems (pkgs: rec {
        waddly = pkgs.callPackage ./nix/package.nix { };
        default = waddly;
      });

      overlays.default = final: _prev: {
        waddly = final.callPackage ./nix/package.nix { };
      };

      darwinModules.default = ./nix/modules/darwin.nix;
      # Nix's flake schema calls this homeModules. Home Manager imports that output.
      homeModules.default = ./nix/modules/home-manager.nix;

      formatter = forSystems checkSystems formatterFor;

      checks = forSystems checkSystems (
        pkgs:
        {
          nixfmt = pkgs.runCommand "nixfmt-check" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
            cd ${nixSrc}
            find flake.nix nix -name '*.nix' -print0 | xargs -0 nixfmt --check
            touch $out
          '';

          modules =
            pkgs.runCommand "waddly-modules"
              {
                homeCount = toString moduleSmoke.homeCount;
                darwinCount = toString moduleSmoke.darwinCount;
                enabledAssertionsHold = if moduleSmoke.enabledAssertionsHold then "yes" else "no";
                disabledLinuxEnable = if moduleSmoke.disabledLinuxEnable then "yes" else "no";
                disabledIntelEnable = if moduleSmoke.disabledIntelEnable then "yes" else "no";
                enabledLinuxRejected = if moduleSmoke.enabledLinuxRejected then "yes" else "no";
              }
              ''
                test "$homeCount" = 1
                test "$darwinCount" = 1
                test "$enabledAssertionsHold" = yes
                test "$disabledLinuxEnable" = no
                test "$disabledIntelEnable" = no
                test "$enabledLinuxRejected" = yes
                touch $out
              '';
        }
        // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "aarch64-darwin") {
          waddly = self.packages.aarch64-darwin.default;
        }
      );
    };
}
