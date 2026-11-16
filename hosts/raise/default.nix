{
  lib,
  lib',
  inputs,
  ...
}:
{
  imports = [
    ../../profiles/proxmox.nix
    inputs.llmhop.nixosModules.default
    inputs.hivegent.nixosModules.default
  ]
  ++ lib'.flocken.getModules ./.;

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "26.05";

  custom.rootDomain = lib.mkDefault "raise.dfki.dev";
  services.caddy.enable = true;

  # DFKI operates this instance and issues Hivegent's additional terms itself.
  services.hivegent.settings.accept_terms = true;
}
