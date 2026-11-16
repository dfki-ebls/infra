{
  inputs,
  self,
  lib,
  lib',
  ...
}:
{
  imports = [
    inputs.treefmt-nix.flakeModule
  ]
  ++ lib'.flocken.getModules ./.;
  systems = import inputs.systems;

  flake.nixpkgsConfig = {
    allowUnfree = true;
    nvidia.acceptLicense = true;
  };

  perSystem =
    { system, pkgs, ... }:
    let
      custom = lib.filterAttrs (_: lib.meta.availableOn pkgs.stdenv.hostPlatform) pkgs.custom;
    in
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config = self.nixpkgsConfig;
        overlays = [
          self.overlays.default
        ];
      };
      checks = custom;
      packages = custom;
      legacyPackages = pkgs;
      treefmt = {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true;
        };
      };
    };
}
