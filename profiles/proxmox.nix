# Proxmox VM guest booting with systemd-boot, whose image `<host>-image` builds.
# https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/proxmox-image.nix
{
  config,
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    "${modulesPath}/virtualisation/proxmox-image.nix"
  ];

  proxmox = {
    qemuConf = {
      name = config.networking.hostName;
      bios = "ovmf";
      cores = lib.mkDefault 8;
      memory = lib.mkDefault (16 * 1024);
      agent = true;
      additionalSpace = lib.mkDefault "8G";
      bootSize = "512M";
    };
    # https://pve.proxmox.com/pve-docs-7/qm.conf.5.html
    qemuExtraConf = {
      cpu = "host";
      machine = "q35";
    };
    cloudInit.enable = false;
  };

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = lib.mkDefault 10;
  };
}
