{ lib, config, ... }:
let
  gateway = config.services.llmhop.gateway.llmhop;
  # Every credential with this prefix is a client token, see README.
  prefix = "llmhop.token.";
  # Clients whose tokens are generated, besides those added by hand.
  clients = [ "hivegent" ];
in
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
      settings.authTokenCredentials = "${prefix}*";
    };
  };

  # Streams flush on their own, and a client disconnecting cancels generation.
  services.caddy.virtualHosts.llmhop = {
    domain = config.custom.rootDomain;
    geoblock = true;
    extraConfig = ''
      reverse_proxy unix/${gateway.listen.default.socket}
    '';
  };

  custom.credstore = lib.mkIf config.services.llmhop.gateway.active (
    lib.genAttrs' clients (
      client: lib.nameValuePair "${prefix}${client}" "od -An -N32 -tx1 /dev/urandom | tr -d ' \\n'"
    )
  );
}
