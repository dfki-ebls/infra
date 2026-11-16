# ZFS mirror over two LUKS2 devices, unlocked by the TPM, with an ESP on each SSD,
# so either one boots on its own. See README for installing and TPM enrollment.
{ lib, ... }:
let
  # Device placeholders, replace with the `/dev/disk/by-id` paths of the SSDs.
  disks = {
    a = {
      device = "/dev/disk/by-id/nvme-Samsung_SSD_9100_PRO_PLACEHOLDER_A";
      esp = "/boot";
    };
    b = {
      device = "/dev/disk/by-id/nvme-Samsung_SSD_9100_PRO_PLACEHOLDER_B";
      esp = "/boot-fallback";
    };
  };
in
{
  disko.devices = {
    disk = lib.mapAttrs (name: disk: {
      type = "disk";
      inherit (disk) device;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = disk.esp;
              mountOptions = [
                "umask=0077"
                "nofail"
              ];
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "crypt-${name}";
              # dm-crypt's workqueues only add latency on SSDs.
              settings = {
                allowDiscards = true;
                bypassWorkqueues = true;
                crypttabExtraOpts = [ "tpm2-device=auto" ];
              };
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
    }) disks;

    zpool.zroot = {
      type = "zpool";
      mode = "mirror";
      options.ashift = "12";
      rootFsOptions = {
        acltype = "posixacl";
        atime = "off";
        compression = "zstd";
        dnodesize = "auto";
        xattr = "sa";
        mountpoint = "none";
      };
      datasets = {
        root = {
          type = "zfs_fs";
          mountpoint = "/";
        };
        nix = {
          type = "zfs_fs";
          mountpoint = "/nix";
        };
        home = {
          type = "zfs_fs";
          mountpoint = "/home";
        };
      };
    };
  };

  # GRUB installs itself into both ESPs, each with its own firmware boot entry.
  # systemd-boot would need a single ESP, which cannot be mirrored without glue.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    configurationLimit = 10;
    mirroredBoots = lib.mapAttrsToList (_: disk: {
      path = disk.esp;
      devices = [ "nodev" ];
    }) disks;
  };

  # Waits for both devices to be unlocked, also through a passphrase prompt,
  # while a missing one fails after its timeout and the pool imports degraded.
  boot.initrd.systemd.services.zfs-import-zroot.after = [ "cryptsetup.target" ];

  networking.hostId = "8b7dcd7e";
  services.zfs.autoScrub.enable = true;
}
