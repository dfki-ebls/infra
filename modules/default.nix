{ lib', inputs, ... }:
{
  imports = [
    inputs.determinate.nixosModules.default
    inputs.disko.nixosModules.default
    inputs.llmhop.nixosModules.default
  ]
  ++ lib'.flocken.getModules ./.;

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "Europe/Berlin";
  documentation.man.cache.enable = false;

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
  # On disk rather than tmpfs, whose pages would compete with the memory that
  # services such as vLLM claim up front.
  boot.tmp.cleanOnBoot = true;

  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # Kills the most pressured service or session once memory pressure stays
  # above 80%, before the kernel OOM killer would, which only acts after the
  # system froze, while systemd restarts killed services as configured.
  systemd.oomd = {
    enableRootSlice = true;
    enableSystemSlice = true;
    enableUserSlices = true;
  };

  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowSuspendThenHibernate = "no";
    AllowHybridSleep = "no";
  };
}
