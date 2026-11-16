# Option modules, each declaring options together with the config implementing
# them, so they stay inert until a host sets them.
{ lib', ... }:
{
  imports = lib'.flocken.getModules ./.;
}
