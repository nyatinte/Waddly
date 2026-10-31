# Evaluates the modules against the aarch64-darwin package set.
# Importing this file does not build Waddly.
{ lib, pkgs }:
let
  eval =
    module: extra:
    lib.evalModules {
      modules = [
        module
        extra
      ];
      specialArgs = { inherit pkgs; };
    };

  home = eval ./modules/home-manager.nix {
    config.programs.waddly.enable = true;
    options.home.packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
    };
  };

  darwin = eval ./modules/darwin.nix {
    config.programs.waddly.enable = true;
    options.environment.systemPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
    };
  };
in
{
  homeCount = builtins.length home.config.home.packages;
  darwinCount = builtins.length darwin.config.environment.systemPackages;
}
