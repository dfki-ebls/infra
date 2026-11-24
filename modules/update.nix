{ ... }:
{
  system.autoUpgrade = {
    enable = true;
    # nixos-rebuild picks the configuration named after the hostname.
    flake = "github:dfki-ebls/infra";
    upgrade = false;
    dates = "04:00";
    allowReboot = true;
    runGarbageCollection = true;
    # The window check compares strictly, so it has to open before `dates`,
    # otherwise a run finishing within 04:00 never reboots.
    rebootWindow = {
      lower = "03:00";
      upper = "05:00";
    };
  };
}
