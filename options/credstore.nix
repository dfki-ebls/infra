{ config, lib, ... }:
let
  credstore = "/etc/credstore";

  # systemd accepts `*` only as the last character of an imported name.
  matches =
    name: pattern:
    if lib.hasSuffix "*" pattern then
      lib.hasPrefix (lib.removeSuffix "*" pattern) name
    else
      pattern == name;

  # Every imported name or glob with its unit, collected once.
  imports = lib.concatLists (
    lib.mapAttrsToList (
      unit: service:
      map (pattern: {
        inherit pattern;
        unit = "${unit}.service";
      }) (lib.toList (service.serviceConfig.ImportCredential or [ ]))
    ) config.systemd.services
  );

  consumers = lib.mapAttrs (
    name: _: lib.unique (map (i: i.unit) (lib.filter (i: matches name i.pattern) imports))
  ) config.custom.credstore;
in
{
  options.custom.credstoreDirectory = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = credstore;
    description = "Directory of the credentials that `ImportCredential=` reads and `custom.credstore` generates.";
  };

  options.custom.credstore = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example."searx.secret-key" = "od -An -N32 -tx1 /dev/urandom | tr -d ' \\n'";
    description = ''
      Credentials generated into `${credstore}` if missing, keyed by name,
      with the shell command printing the secret as value. Each is generated
      before every service importing it and never overwritten.
    '';
  };

  config = {
    assertions = lib.mapAttrsToList (name: units: {
      assertion = units != [ ];
      message = "custom.credstore.${name} is imported by no service, so it would never be generated.";
    }) consumers;

    systemd.services = lib.mapAttrs' (
      name: generate:
      lib.nameValuePair "credstore-${name}" {
        description = "Generate credential ${name} if missing";
        requiredBy = consumers.${name};
        before = consumers.${name};
        unitConfig.ConditionPathExists = "!${credstore}/${name}";
        serviceConfig = {
          Type = "oneshot";
          UMask = "0077";
        };
        script = ''
          set -o pipefail
          secret=$(${generate})
          printf '%s' "$secret" > ${credstore}/${name}
        '';
      }
    ) config.custom.credstore;
  };
}
