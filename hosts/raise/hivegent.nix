{
  lib,
  config,
  inputs,
  ...
}:
let
  vhost = config.services.caddy.virtualHosts.hivegent;
  hivegentUrl = vhost.url;
  inherit (config.custom.rauthy) issuer origin;

  # Every OIDC client whose tokens the API accepts, matched exactly, since a
  # prefix would admit any client an IdP admin later names alike. The SPA one
  # is the backend's default `auth.frontend_client_id`.
  spaClient = "hivegent-spa";
  integrationClient = "hivegent-integration";

  # The models and the watermark detector are served by pythia's llmhop, which
  # authenticates Hivegent with the key of its client `hivegent`, the
  # credential `hivegent.LLM__PROVIDERS__PYTHIA__API_KEY`, see README.
  pythia = inputs.self.nixosConfigurations.pythia.config;
  pythiaUrl = pythia.services.caddy.virtualHosts.root.url;
  # pythia's public address, which `IPAddressAllow` needs in place of its name.
  pythiaAddress = "136.199.45.191";
  inherit (pythia.services.llmhop.vllm) models detectors;
  chatModel = "qwen3.8-27b";
  auxModel = "qwen3.6-35b-a3b";
  # The model's own limit, since it rejects a request over it.
  maxImages = model: models.${model}.settings.limit-mm-per-prompt.image.count;
  withTransparency = lib.mkIf (detectors ? watermark);
  # 32 random bytes in hex.
  secret = "od -An -N32 -tx1 /dev/urandom | tr -d ' \\n'";

  # Web search and fetching follow the local SearXNG below.
  withWeb = lib.mkIf config.services.searx.enable;
in
{
  services.hivegent = {
    enable = true;

    postgresql.createLocally = true;
    searxng.createLocally = config.services.searx.enable;

    # Rauthy is reached via split-horizon and Postgres via its unix socket, so
    # pythia is the only endpoint beyond loopback.
    allowedAddresses = [ pythiaAddress ];

    settings = {
      auth = {
        inherit issuer;
        audience = [
          spaClient
          integrationClient
        ];
      };

      # 32-core, 128 GB host shared with the LLM servers, Postgres, and Rauthy.
      compute = {
        # Each worker converts one document at a time and holds its own models
        # (about 4-6 GB on CPU), so 8 stay well within memory.
        worker_processes = 8;
        # Total budget split across the workers (3 each), since Tesseract's
        # OpenMP scales sublinearly and parallel documents beat wider OCR.
        # The rest stays with embeddings, Postgres, and the other services.
        num_threads = 24;
      };

      jobs = {
        # Enough files in flight that a single collection import fills the
        # worker pool, while the rest queue on it.
        max_concurrency = 4;
        collection_concurrency = 8;
      };

      # Short-lived pdfium paging processes, light next to the pool.
      isolation.max_workers = 4;

      conversion = {
        # The corpus is German-only; each extra OCR language widens
        # Tesseract's beam search (~25% slower with deu+eng).
        ocr.languages = [ "deu" ];
      };

      llm = {
        default = chatModel;
        aux = auxModel;
        providers.pythia = {
          base_url = "${pythiaUrl}/v1";
          inference_provider = "vllm";
        };
        models = {
          ${chatModel} = {
            provider = "pythia";
            model = chatModel;
            vision = true;
            max_images = maxImages chatModel;
            # Qwen3.8 implements `xhigh` in place of `high`.
            reasoning_overrides.high = "xhigh";
          };
          # Only fills the aux role, with reasoning off.
          ${auxModel} = {
            provider = "pythia";
            model = auxModel;
            vision = true;
            max_images = maxImages auxModel;
            chat = false;
          };
        };
      };

      # Lets web_fetch open any public page the user or a search named.
      security = withWeb { web_urls.allow_hosts = [ "*" ]; };

      # Advertised in web_fetch's User-Agent for traffic questions.
      network.contact_email = config.custom.admin.mail;

      transparency = withTransparency {
        endpoint = "pythia";
        detector_path = "/llmhop/proxy/${detectors.watermark.name}/detect";
        report_issuer = hivegentUrl;
        contact_email = config.custom.admin.mail;
      };
    };

    caddy = {
      enable = true;
      hostName = vhost.address;
      hsts = config.custom.enableCertificates;
      # The SPA's Content-Security-Policy lets it reach and frame Rauthy for
      # the sign-in and session restoration.
      idpOrigins = [ origin ];
    };
  };

  custom.credstore = lib.mkMerge [
    (withTransparency {
      "hivegent.TRANSPARENCY__SECRET_KEY" = secret;
    })
    (withWeb {
      "searx.secret-key" = secret;
    })
  ];

  # Web search through a local SearXNG and fetching of the pages it or the
  # user names, off until the shared instance should reach the web.
  services.searx = {
    enable = false;
    settings = {
      # Substituted by searx-init when it renders the settings.
      server.secret_key = "$SEARX_SECRET_KEY";
      # The corpus is German, so a search naming no language finds German pages.
      search.default_lang = "de";
    };
  };

  systemd.services.searx-init = withWeb {
    serviceConfig.ImportCredential = "searx.secret-key";
    script = lib.mkBefore ''
      SEARX_SECRET_KEY=$(< "$CREDENTIALS_DIRECTORY/searx.secret-key")
      export SEARX_SECRET_KEY
    '';
  };

  # Bootstrap only the SPA client, public without a secret, so Rauthy enforces
  # S256 PKCE. Rauthy emits roles without a dedicated scope, while groups need
  # the groups scope.
  custom.rauthy.bootstrap.clients = [
    rec {
      id = spaClient;
      name = "Hivegent";
      client_uri = hivegentUrl;
      contacts = [ config.custom.admin.mail ];
      redirect_uris = [ "${hivegentUrl}/" ];
      post_logout_redirect_uris = redirect_uris;
      allowed_origins = [ hivegentUrl ];
      enabled = true;
      flows_enabled = [
        "authorization_code"
        "refresh_token"
      ];
      access_token_alg = "EdDSA";
      id_token_alg = "EdDSA";
      auth_code_lifetime = 60;
      access_token_lifetime = 1800;
      scopes = [
        "openid"
        "profile"
        "email"
        "groups"
      ];
      default_scopes = scopes;
      force_mfa = false;
    }
  ];

  # The module's site body brings its own security headers.
  services.caddy.virtualHosts.hivegent = {
    subdomain = "hivegent";
    vpnOnly = true;
    geoblock = true;
    scannerHoneypots = true;
    securityHeaders.enable = false;
  };

  systemd.services.hivegent = {
    # Discovery from the public issuer goes through Caddy to Rauthy at startup.
    # Ordering only, since Caddy restarts on every vhost change here and a
    # requirement would restart the backend and reload its models with it.
    after = [
      "caddy.service"
      "rauthy.service"
    ];
  };
}
