{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  # Production serves the website at raise.dfki.de.
  production = config.custom.rootDomain == "raise.dfki.dev";
in
{
  services.caddy.virtualHosts = {
    websiteAlias = lib.mkIf production {
      domain = config.custom.rootDomain;
      extraConfig = ''
        redir https://raise.dfki.de{uri}
      '';
    };
    website = {
      domain = if production then "raise.dfki.de" else config.custom.rootDomain;
      # Starlight's pages carry inline scripts, which `default-src` would block
      # without their hashes, so every other fetch directive is listed instead.
      securityHeaders.contentSecurityPolicy = {
        connect-src = [ "'self'" ];
        img-src = [
          "'self'"
          "data:"
        ];
        font-src = [ "'self'" ];
        style-src = [
          "'self'"
          "'unsafe-inline'"
        ];
        media-src = [ "'none'" ];
        frame-src = [ "'none'" ];
        worker-src = [ "'none'" ];
        manifest-src = [ "'none'" ];
        object-src = [ "'none'" ];
        base-uri = [ "'none'" ];
        form-action = [ "'none'" ];
      };
      extraConfig = ''
        root * ${inputs.website.packages.${pkgs.stdenv.system}.default}
        encode

        @immutable path /assets/*
        header @immutable Cache-Control "public, max-age=31536000, immutable"

        @html not path /assets/*
        header @html Cache-Control "no-store"

        header {
          -ETag
          -Last-Modified
        }

        file_server

        handle_errors {
          @404 expression {http.error.status_code} == 404
          rewrite @404 /404.html
          file_server
        }
      '';
    };
  };
}
