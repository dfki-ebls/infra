{ inputs, ... }:
{
  nix = {
    channel.enable = false;
    gc = {
      automatic = true;
      options = "--delete-older-than 7d";
    };
    optimise = {
      automatic = true;
    };
    extraOptions = ''
      !include nix.secrets.conf
    '';
    settings = {
      sandbox = true;
      allowed-users = [ "@wheel" ];
      extra-trusted-substituters = [
        "https://dfki-ebls.cachix.org"
        "https://mirkolenz.cachix.org"
      ];
      extra-trusted-public-keys = [
        "dfki-ebls.cachix.org-1:hImWYLrtbzgibnK8e09XXT2EID923m6D08fHmASB/kE="
        "mirkolenz.cachix.org-1:R0dgCJ93t33K/gncNbKgUdJzwgsYVXeExRsZNz5jpho="
      ];
      experimental-features = [
        "flakes"
        "nix-command"
        "pipe-operators"
      ];
      commit-lock-file-summary = "chore(deps): update flake.lock";
      download-buffer-size = 1000000000; # 1 GB
      keep-derivations = true;
      keep-failed = false;
      keep-going = true;
      keep-outputs = false;
      log-lines = 200;
      warn-dirty = false;
    };
  };
  nixpkgs = {
    config = inputs.self.nixpkgsConfig;
    overlays = [
      inputs.self.overlays.default
    ];
  };
}
