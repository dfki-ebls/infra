# Installer images of every Linux system, as `legacyPackages.<system>.installer`
# holding every variant of `system.build.images`, such as `iso-installer`.
{
  inputs,
  lib,
  lib',
  ...
}:
{
  perSystem =
    { system, ... }:
    {
      config = lib.mkIf (lib.hasSuffix "-linux" system) {
        legacyPackages.installer =
          (inputs.nixpkgs.lib.nixosSystem {
            system = null;
            specialArgs = {
              inherit inputs lib';
            };
            modules = [
              ../profiles/installer.nix
              { nixpkgs.hostPlatform = system; }
            ];
          }).config.system.build.images;
      };
    };
}
