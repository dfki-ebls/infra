{ lib', inputs, ... }:
{
  imports = [
    inputs.determinate.nixosModules.default
  ]
  ++ lib'.flocken.getModules ./.;

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "Europe/Berlin";
  documentation.man.cache.enable = false;
  hardware.enableAllFirmware = true;

  security = {
    lockKernelModules = true;
    protectKernelImage = true;
    sudo-rs = {
      enable = true;
      execWheelOnly = true;
    };
  };

  environment = {
    variables.BROWSER = "echo";
  };

  boot.loader.efi.canTouchEfiVariables = true;

  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowSuspendThenHibernate = "no";
    AllowHybridSleep = "no";
  };
}
