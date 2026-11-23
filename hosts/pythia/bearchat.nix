# Chat interface at `/chat`, on the same origin as llmhop, whose tokens sign
# users in, see README.
{ inputs, config, ... }:
{
  imports = [ inputs.bearchat.nixosModules.default ];

  services.bearchat = {
    enable = true;
    virtualHost = "root";
    # The root path would shadow llmhop's routes under `/v1` and `/llmhop`.
    path = "/chat";
    upstream = "unix/${config.services.llmhop.gateway.listen.default.socket}";
    settings.locked.model = "qwen3.8-27b";
  };
}
