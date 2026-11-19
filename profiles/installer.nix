# Installer image reachable over SSH as root with the admin's keys, for
# installing a host as its README section describes.
# It ships the hosts' NVIDIA driver, so `nvidia-smi` lists the GPUs in PCI bus
# order before installing, as the README asks.
{
  config,
  inputs,
  modulesPath,
  ...
}:
{
  imports = [
    inputs.determinate.nixosModules.default
    ../options/admin.nix
    ../modules/admin.nix
    ../options/nvidia.nix
    # Declares `system.installer.channel.enable`, which the image variants
    # otherwise only get through their installation profiles.
    "${modulesPath}/installer/cd-dvd/channel.nix"
  ];

  # Unfree, for the NVIDIA driver.
  nixpkgs.config = inputs.self.nixpkgsConfig;

  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = config.custom.admin.sshKeys;

  # Hosts install from the flake, so no channel is needed.
  nix.channel.enable = false;
  system.installer.channel.enable = false;

  # determinate-nixd writes the nix.conf including the nix settings only once
  # its daemon started, which on demand happens after the first client read
  # its config on the fresh live system.
  systemd.services.nix-daemon.wantedBy = [ "multi-user.target" ];
}
