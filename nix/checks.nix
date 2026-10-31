# Evaluates the modules. Importing this file does not build Waddly.
{ lib, pkgsBySystem }:
let
  assertionModule = {
    options.assertions = lib.mkOption {
      type = lib.types.listOf lib.types.unspecified;
      default = [ ];
    };
  };

  eval =
    system: module: extra:
    lib.evalModules {
      modules = [
        module
        assertionModule
        extra
      ];
      specialArgs.pkgs = pkgsBySystem.${system};
    };

  homePackages = {
    options.home.packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
    };
  };

  darwinPackages = {
    options.environment.systemPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
    };
  };

  enabledHome = eval "aarch64-darwin" ./modules/home-manager.nix (
    homePackages // { config.programs.waddly.enable = true; }
  );
  enabledDarwin = eval "aarch64-darwin" ./modules/darwin.nix (
    darwinPackages // { config.programs.waddly.enable = true; }
  );
  disabledLinux = eval "x86_64-linux" ./modules/home-manager.nix homePackages;
  disabledIntel = eval "x86_64-darwin" ./modules/darwin.nix darwinPackages;
  enabledLinux = eval "x86_64-linux" ./modules/home-manager.nix (
    homePackages // { config.programs.waddly.enable = true; }
  );

  failed = config: builtins.filter (assertion: !assertion.assertion) config.assertions;
in
{
  homeCount = builtins.length enabledHome.config.home.packages;
  darwinCount = builtins.length enabledDarwin.config.environment.systemPackages;
  enabledAssertionsHold = failed enabledHome.config == [ ] && failed enabledDarwin.config == [ ];
  disabledLinuxEnable = disabledLinux.config.programs.waddly.enable;
  disabledIntelEnable = disabledIntel.config.programs.waddly.enable;
  enabledLinuxRejected = builtins.length (failed enabledLinux.config) == 1;
}
