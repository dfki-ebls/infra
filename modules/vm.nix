# Tests the system of a host, with a throwaway disk instead of its real ones.
{ config, ... }:
{
  virtualisation.vmVariant = {
    custom.enableNvidia = false;
    users.users.${config.custom.admin.login}.password = "";
    security.sudo-rs.wheelNeedsPassword = false;
    virtualisation = {
      graphics = false;
      cores = 8;
      memorySize = 16 * 1024;
      forwardPorts = [
        {
          from = "host";
          host.port = 2222;
          guest.port = 22;
        }
      ];
    };
  };
}
