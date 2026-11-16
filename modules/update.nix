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
    rebootWindow = {
      lower = "04:00";
      upper = "05:00";
    };
  };
}
