# Headless vLLM inference server.
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
