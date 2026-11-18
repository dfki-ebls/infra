{
  config,
  pkgs,
  inputs,
  ...
}:
let
  admin = config.custom.admin;

  ragold = inputs.ragold.packages.${pkgs.stdenv.system}.default.overrideAttrs {
    VITE_CONTACT_INFO = "${admin.name} <${admin.mail}>";
  };
in
{
  # Lets users transfer a Hivegent reply to RAGold as a gold benchmark entry.
  services.hivegent.settings.ragold.url = config.services.caddy.virtualHosts.ragold.url;

  services.caddy.virtualHosts.ragold = {
    subdomain = "ragold";
    # The viewers render uploads as blob and data URLs, in blob workers for
    # PDFs and spreadsheets, and the UI sets inline styles.
    securityHeaders.contentSecurityPolicy = {
      default-src = [ "'self'" ];
      connect-src = [
        "'self'"
        "blob:"
        "data:"
      ];
      img-src = [
        "'self'"
        "blob:"
        "data:"
      ];
      font-src = [
        "'self'"
        "data:"
      ];
      style-src = [
        "'self'"
        "'unsafe-inline'"
      ];
      worker-src = [
        "'self'"
        "blob:"
      ];
      object-src = [ "'none'" ];
      base-uri = [ "'none'" ];
      form-action = [ "'none'" ];
    };
    extraConfig = ''
      root * ${ragold}
      encode

      header {
        -ETag
        -Last-Modified
      }

      handle /assets/* {
        header Cache-Control "public, max-age=31536000, immutable"
        file_server
      }

      handle {
        header Cache-Control "no-store"
        try_files {path} /index.html
        file_server
      }
    '';
  };
}
