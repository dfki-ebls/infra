# ZFS mirror over two LUKS2 devices, unlocked by the TPM, with an ESP on each SSD,
# so either one boots on its own. See README for TPM enrollment.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  # By slot, so a replacement in the same slot needs no change, see README.
  disks = {
    a = {
      device = "/dev/disk/by-path/pci-0000:a9:00.0-nvme-1";
      esp = "/boot";
    };
    b = {
      device = "/dev/disk/by-path/pci-0000:aa:00.0-nvme-1";
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
              # Matches the pool's 4 KiB blocks (ashift 12), so dm-crypt
              # encrypts one sector per block instead of eight.
              extraFormatArgs = [ "--sector-size=4096" ];
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

  # systemd-boot installs into the primary ESP only, so every rebuild mirrors it to
  # the fallback, whose removable path `EFI/BOOT/BOOTX64.EFI` the firmware boots
  # when the primary SSD is missing. The random seed stays on the primary, since a
  # copy would reuse it. A failing fallback only warns, so deployments still work.
  boot.loader.efi.efiSysMountPoint = disks.a.esp;
  boot.loader.systemd-boot = {
    enable = true;
    editor = false;
    configurationLimit = 10;
    extraInstallCommands = ''
      if ${lib.getExe' pkgs.util-linuxMinimal "mountpoint"} -q ${disks.b.esp}; then
        ${lib.getExe pkgs.rsync} --recursive --times --modify-window=1 --delete \
          --exclude=/loader/random-seed ${disks.a.esp}/ ${disks.b.esp}/ &&
          ${lib.getExe' pkgs.coreutils "sync"} --file-system ${disks.b.esp} ||
          echo "mirroring to ${disks.b.esp} failed" >&2
      else
        echo "${disks.b.esp} is not mounted, skipping the ESP mirror" >&2
      fi
    '';
  };

  # Waits for both devices to be unlocked, also through a passphrase prompt,
  # while a missing one fails after its timeout and the pool imports degraded.
  boot.initrd.systemd.services.zfs-import-zroot.after = [ "cryptsetup.target" ];

  networking.hostId = "8b7dcd7e";
  services.zfs.autoScrub.enable = true;
}
