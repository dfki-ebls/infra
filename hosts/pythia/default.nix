# Headless vLLM inference server, with the RTX A400 driving the display for maintenance.
{
  lib,
  lib',
  inputs,
  ...
}:
{
  imports = [
    inputs.llmhop.nixosModules.default
  ]
  ++ lib'.flocken.getModules ./.;

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "26.11";

  custom.rootDomain = lib.mkDefault "pythia.dfki.dev";
  services.caddy.enable = true;
}
