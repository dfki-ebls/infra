{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.rauthy;

  vhosts = config.services.caddy.virtualHosts;
  pubUrl = vhosts.rauthy.domain;
  pubOrigin = vhosts.rauthy.url;

  port = 8080;
  mail = "raise@wi2.uni-trier.de";

  credential = "rauthy.secrets";
  fromSecrets = "$SECRETS";
  rauthy = lib.getExe cfg.package;
in
{
  # Rauthy's own generators print the `[cluster]` and `[encryption]` tables.
  custom.credstore.${credential} = "${rauthy} generate-secrets && ${rauthy} generate-enc-key";

  custom.rauthy = {
    enable = true;
    origin = pubOrigin;
    postgresql.createLocally = true;
    secretsCredential = credential;
    # `SMTP_PASSWORD`, see README.
    environmentFile = "/etc/rauthy/rauthy.env";

    settings = {
      bootstrap = {
        # Rauthy logs the one-time password for this user on first DB init.
        admin_email = config.custom.admin.mail;
      };

      # Put the client id into the `sub` of client_credentials tokens.
      # Without it those tokens carry no `sub`, and downstream APIs that key
      # a principal on `sub` (Hivegent) reject them.
      access.client_credentials_map_sub = true;

      cluster = {
        # https://sebadob.github.io/rauthy/config/ha.html
        node_id = 1;
        nodes = [ "1 localhost:8100 localhost:8200" ];
        secret_raft = fromSecrets;
        secret_api = fromSecrets;
      };

      encryption = {
        keys = [ fromSecrets ];
        key_active = fromSecrets;
      };

      server = {
        listen_address = "127.0.0.1";
        port_http = port;
        scheme = "http";
        pub_url = pubUrl;
        # Keep the local VM HTTP-only when certificates are disabled.
        proxy_mode = config.custom.enableCertificates;
        trusted_proxies = [ "127.0.0.1/32" ];
      };

      # Populating WebAuthn enables passkeys in Rauthy.
      webauthn = {
        rp_id = pubUrl;
        rp_origin = "${pubOrigin}:${if config.custom.enableCertificates then "443" else "80"}";
        rp_name = "RAISE Single Sign-On";
        # Require PIN or biometric verification for passkey MFA.
        force_uv = true;
      };

      user_registration.enable = false;

      # SMTP via the uni Trier relay. Port 465 (implicit TLS/SSL) maps to
      # Rauthy's default connection mode, which builds a lettre `relay()`
      # transport over TLS. https://sebadob.github.io/rauthy/config/config.html
      email = {
        rauthy_admin_email = config.custom.admin.mail;
        smtp_url = "mail.wi2.uni-trier.de";
        smtp_port = 465;
        smtp_username = mail;
        smtp_from = "RAISE Single Sign-On <${mail}>";
        sub_prefix = "RAISE Single Sign-On";
      };

      events.email = config.custom.admin.mail;

      suspicious_requests.log = false;
    };
  };

  services.caddy.virtualHosts.rauthy = {
    subdomain = "sso";
    vpnOnly = true;
    geoblock = true;
    # Replaces Rauthy's own policy, so keeps its `object-src`. oidc-spa restores
    # sessions through a hidden authorization iframe, so Rauthy must allow the
    # Hivegent SPA origin to frame auth responses.
    securityHeaders.contentSecurityPolicy = {
      frame-ancestors = [ vhosts.hivegent.address ];
      object-src = [ "'none'" ];
    };
    extraConfig = ''
      reverse_proxy 127.0.0.1:${toString port}
    '';
  };

  # Split-horizon for local relying parties such as Hivegent, which is confined
  # to loopback and passes the VPN allowlist there, so the public issuer
  # resolves to this host's Caddy, keeping URL and TLS name.
  networking.hosts = {
    "127.0.0.1" = [ pubUrl ];
    "::1" = [ pubUrl ];
  };
}
