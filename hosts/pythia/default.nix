# Headless vLLM inference server, with the RTX A400 driving the display for maintenance.
{ lib, lib', ... }:
{
  imports = lib'.flocken.getModules ./.;

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "26.11";

  custom = {
    rootDomain = lib.mkDefault "pythia.dfki.uni-trier.de";
    # Issued by the university, see README.
    installedCertificates = true;
  };
  services.caddy.enable = true;
}
