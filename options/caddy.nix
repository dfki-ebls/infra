# Caddy with its global settings once a host enables it, and vhosts below
# `custom.rootDomain`, each deriving its site address from its domain and
# adding the shared hardening it opts into.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom;

  # Response headers of a vhost, where null deletes a header. Deleting makes
  # Caddy defer the block until the response is written, so it also replaces
  # the headers of a proxied app and of any header directive sorted before it.
  # Browsers enforce the intersection of all CSP headers, so the policy is
  # emitted once here, where `frame-ancestors` supersedes X-Frame-Options.
  securityHeaders =
    contentSecurityPolicy:
    {
      Content-Security-Policy = lib.concatStringsSep "; " (
        lib.mapAttrsToList (
          directive: sources: "${directive} ${lib.concatStringsSep " " sources}"
        ) contentSecurityPolicy
      );
      X-Content-Type-Options = "nosniff";
      X-Frame-Options = null;
      Server = null;
    }
    // lib.optionalAttrs cfg.enableCertificates {
      Strict-Transport-Security = "max-age=31536000; includeSubDomains";
    };

  renderHeaders = headers: ''
    header {
    ${
      lib.concatStrings (
        lib.mapAttrsToList (
          name: value: if value == null then "  -${name}\n" else "  ${name} \"${value}\"\n"
        ) headers
      )
    }}
  '';

  # Server-local `client_ip` allowlist for internal services, resolved when
  # Caddy adapts its config at startup. The directory lives only on the server,
  # so the allowlist changes with a `systemctl restart caddy`, no rebuild.
  # Loopback stays allowed for local clients such as Hivegent's OIDC discovery,
  # and keeps the matcher non-empty, since an import glob matching no files is
  # a no-op, so everyone else is denied if the drop-ins are missing.
  vpnAllowlist = ''
    @vpn_blocked not {
      client_ip 127.0.0.0/8 ::1
      import /etc/caddy/vpn.d/*.caddy
    }
    handle @vpn_blocked {
      respond "Access denied: Your IP is not allowed to access this resource." 403
    }
  '';

  # Private ranges (e.g., VPN clients) have no country and are exempt.
  geoblock = ''
    @geoblocked {
      not client_ip private_ranges
      not {
        maxmind_geolocation {
          db_path ${pkgs.dbip-country-lite.mmdb}
          allow_countries DE
        }
      }
    }
    handle @geoblocked {
      respond "Access denied: Your location is not allowed to access this resource." 403
    }
  '';

  installedCertificates = cfg.enableCertificates && cfg.installedCertificates;
  certificateCredentials = [
    "caddy.tls.cert"
    "caddy.tls.key"
  ];
  installedTls = ''
    tls ${lib.concatMapStringsSep " " (name: "{$CREDENTIALS_DIRECTORY}/${name}") certificateCredentials}
  '';

  # Curated honeypot paths we never serve.
  scannerHoneypots = ''
    @scanner path /wp-admin* /wp-login* /wp-content* /xmlrpc.php /phpmyadmin* /pma* /.aws/* /.ssh/* /administrator /admin.php /shell.php
    handle @scanner {
      respond 404
    }
  '';

  vhostModule =
    { config, ... }:
    {
      options = {
        subdomain = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          example = "sso";
          description = "Subdomain of `custom.rootDomain` the vhost serves, setting `domain`.";
        };
        domain = lib.mkOption {
          type = with lib.types; nullOr str;
          default = if config.subdomain == null then null else "${config.subdomain}.${cfg.rootDomain}";
          defaultText = lib.literalExpression ''"''${subdomain}.''${config.custom.rootDomain}"'';
          description = "Domain the vhost serves, setting `hostName`.";
        };
        address = lib.mkOption {
          type = with lib.types; nullOr str;
          readOnly = true;
          default = if cfg.enableCertificates then config.domain else config.url;
          description = "Caddy site address of `domain`, plain HTTP without certificates.";
        };
        url = lib.mkOption {
          type = with lib.types; nullOr str;
          readOnly = true;
          default = lib.mapNullable (
            domain: "${if cfg.enableCertificates then "https" else "http"}://${domain}"
          ) config.domain;
          description = "Absolute URL of `domain`, for OIDC issuers, redirect URIs, and origins.";
        };
        vpnOnly = lib.mkEnableOption "restricting the vhost to loopback and the allowlist in `/etc/caddy/vpn.d` if `custom.enableVpnAllowlist`";
        geoblock = lib.mkEnableOption "blocking clients outside Germany if `custom.enableGeoblocking`";
        scannerHoneypots = lib.mkEnableOption "answering 404 to the paths vulnerability scanners probe";
        securityHeaders = {
          enable = lib.mkEnableOption "the baseline security headers" // {
            default = true;
          };
          contentSecurityPolicy = lib.mkOption {
            type = with lib.types; attrsOf (listOf str);
            example = {
              default-src = [ "'self'" ];
              object-src = [ "'none'" ];
            };
            description = ''
              Content-Security-Policy of the vhost, as sources in CSP syntax by
              directive, denying framing unless it sets `frame-ancestors`.
            '';
          };
        };
      };

      config = {
        hostName = lib.mkIf (config.domain != null) (lib.mkDefault config.address);
        securityHeaders.contentSecurityPolicy.frame-ancestors = lib.mkDefault [ "'none'" ];
        extraConfig = lib.mkBefore (
          lib.concatStrings (
            lib.optional (config.vpnOnly && cfg.enableVpnAllowlist) vpnAllowlist
            ++ lib.optional (config.geoblock && cfg.enableGeoblocking) geoblock
            ++ lib.optional config.securityHeaders.enable (
              renderHeaders (securityHeaders config.securityHeaders.contentSecurityPolicy)
            )
            ++ lib.optional config.scannerHoneypots scannerHoneypots
            ++ lib.optional installedCertificates installedTls
          )
        );
      };
    };
in
{
  options = {
    custom = {
      rootDomain = lib.mkOption {
        type = lib.types.str;
        description = "The root domain for all services.";
      };
      enableGeoblocking = lib.mkEnableOption "country geoblocking for Caddy" // {
        default = true;
      };
      enableVpnAllowlist = lib.mkEnableOption "the VPN allowlist of `vpnOnly` vhosts" // {
        default = true;
      };
      enableCertificates = lib.mkEnableOption "secure connections for services" // {
        default = true;
      };
      installedCertificates = lib.mkEnableOption "serving the installed certificate files `caddy.tls.cert` and `caddy.tls.key` from the credential store instead of ACME certificates";
    };

    services.caddy.virtualHosts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule vhostModule);
    };
  };

  config = lib.mkIf config.services.caddy.enable {
    # Every vhost serves the installed certificate, so without it Caddy is
    # skipped rather than failing to load or falling back to ACME.
    systemd.services.caddy = lib.mkIf installedCertificates {
      serviceConfig.ImportCredential = certificateCredentials;
      unitConfig.ConditionPathExists = map (
        name: "${cfg.credstoreDirectory}/${name}"
      ) certificateCredentials;
    };

    services.caddy = {
      package = pkgs.caddy-custom;
      openFirewall = true;
      email = lib.mkIf (!installedCertificates) config.custom.admin.mail;
      enableReload = false; # requires admin api
      globalConfig = lib.mkMerge [
        (lib.mkIf installedCertificates "auto_https disable_certs")
        ''
          admin off
          persist_config off

          # Slow-loris limits. The header timeout is the effective guard;
          # read_body must stay generous because it spans the entire request
          # body transfer — a 50 MB document upload on a slow uplink
          # (~2 Mbit/s) takes minutes, and tripping the timeout mid-body
          # surfaces as an opaque 502 from the reverse proxy.
          servers {
            timeouts {
              read_header 10s
              read_body   10m
              idle        2m
            }
          }
        ''
      ];
    };

    # Serves the vhosts as subdomains of localhost over HTTP on the host's port 80.
    virtualisation.vmVariant = {
      custom = {
        rootDomain = "localhost";
        enableGeoblocking = false;
        enableVpnAllowlist = false;
        enableCertificates = false;
      };
      services.caddy.globalConfig = ''
        auto_https off
      '';
      # glibc needs resolved for wildcard localhost names inside the guest.
      services.resolved.enable = true;
      virtualisation.forwardPorts = [
        {
          from = "host";
          host.port = 80;
          guest.port = 80;
        }
      ];
    };
  };
}
