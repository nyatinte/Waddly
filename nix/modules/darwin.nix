{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.waddly;
in
{
  options.programs.waddly = {
    enable = lib.mkEnableOption "Waddly";

    package = lib.mkOption {
      type = lib.types.package;
      default = if pkgs ? waddly then pkgs.waddly else pkgs.callPackage ../package.nix { };
      defaultText = lib.literalExpression "pkgs.waddly or (pkgs.callPackage ../package.nix { })";
      description = "Waddly package to install.";
    };
  };

  # nix-darwin copies bundles under $out/Applications to /Applications/Nix Apps.
  # Preferences stay in the app; this module only installs the package.
  config = lib.mkIf cfg.enable (
    lib.throwIf (pkgs.stdenv.hostPlatform.system != "aarch64-darwin")
      "Waddly publishes an Apple Silicon DMG only, so programs.waddly supports aarch64-darwin only."
      {
        environment.systemPackages = [ cfg.package ];
      }
  );
}
