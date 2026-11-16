# Every directory in `hosts` is a NixOS configuration named after it, on top of
# the shared `options` and `modules`. Each host gets a `<host>-vm` package for
# testing on the build machine's CPU, and a `<host>-image` package if it builds
# a disk image.
{
  inputs,
  self,
  lib,
  lib',
  ...
}:
let
  hosts = map baseNameOf (lib'.flocken.getModules ../hosts);
in
{
  flake.nixosConfigurations = lib.genAttrs hosts (
    name:
    inputs.nixpkgs.lib.nixosSystem {
      system = null;
      specialArgs = {
        inherit inputs lib';
      };
      modules = [
        ../options
        ../modules
        ../hosts/${name}
        { networking.hostName = name; }
      ];
    }
  );

  perSystem =
    { system, pkgs, ... }:
    {
      packages = lib.concatMapAttrs (
        name: host:
        let
          inherit (host.config.system) build;
          vm = host.extendModules {
            modules = [
              {
                virtualisation.vmVariant = {
                  nixpkgs.hostPlatform = lib.mkForce "${pkgs.stdenv.hostPlatform.parsed.cpu.name}-linux";
                  virtualisation.host.pkgs = pkgs;
                };
              }
            ];
          };
        in
        {
          "${name}-vm" = vm.config.system.build.vm;
        }
        // lib.optionalAttrs (host.pkgs.stdenv.hostPlatform.system == system && build ? image) {
          "${name}-image" = build.image;
        }
      ) self.nixosConfigurations;
    };
}
