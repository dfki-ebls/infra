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
      extraConfig = ''
        root * ${inputs.website.packages.${pkgs.stdenv.system}.default}
        encode zstd gzip

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
