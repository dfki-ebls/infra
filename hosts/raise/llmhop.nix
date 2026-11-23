{ config, ... }:
{
  services.llmhop.gateway = {
    enable = true;
    # Unix socket only, which members of llmhop's group can use, see README.
    listen.default.socketGroup = config.services.llmhop.gateway.group;
  };
}
