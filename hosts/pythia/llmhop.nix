{ config, ... }:
{
  services.llmhop.gateway = {
    enable = true;
    # Unix socket only, which Caddy serves over TLS, so keys never travel in
    # plain text.
    listen.default.socketGroup = config.services.caddy.group;
    settings = {
      # Admins reach it without a key, such as through an SSH port forward.
      clients.admin.listener = "wheel";
      # Every credential `llmhop.api-key.<client>` is a client, see README.
      clientCredentials = true;
    };
  };

  # Streams flush on their own, and a client disconnecting cancels generation.
  services.caddy.virtualHosts.root.extraConfig = ''
    reverse_proxy unix/${config.services.llmhop.gateway.listen.default.socket}
  '';
}
