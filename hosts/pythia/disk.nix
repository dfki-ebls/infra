# ZFS mirror over both SSDs with an ESP on each, so either one boots on its own.
{ lib, config, ... }:
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
    disk = lib.mapAttrs (_: disk: {
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
          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "zroot";
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
        # vLLM memory-maps the weights, which the page cache then holds,
        # so the ARC only keeps their metadata instead of a second copy.
        # OpenZFS keeps a partially read record until it is read through,
        # so the page-sized faults do not reread whole records.
        vllm = {
          type = "zfs_fs";
          mountpoint = config.services.llmhop.vllm.cache.directory;
          options = {
            primarycache = "metadata";
            recordsize = "1M";
          };
        };
        # Unused space that keeps a full pool writable for deleting files,
        # released with `zfs set refreservation=none zroot/reserved`.
        reserved = {
          type = "zfs_fs";
          options = {
            mountpoint = "none";
            refreservation = "50G";
          };
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

  networking.hostId = "8b7dcd7e";
  services.zfs.autoScrub.enable = true;
}
