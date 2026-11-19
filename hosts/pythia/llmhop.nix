{ config, ... }:
{
  services.llmhop.gateway = {
    type = "llmhop";
    llmhop = {
      # Unix socket only, which Caddy serves over TLS, so tokens never travel
      # in plain text.
      listen.default = {
        port = null;
        socketGroup = config.services.caddy.group;
      };
      # Every credential with this prefix is a client token, see README.
      settings.authTokenCredentials = "llmhop.token.*";
    };
  };

  # Streams flush on their own, and a client disconnecting cancels generation.
  services.caddy.virtualHosts.root.extraConfig = ''
    reverse_proxy unix/${config.services.llmhop.gateway.llmhop.listen.default.socket}
  '';
}
