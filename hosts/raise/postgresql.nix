{
  lib,
  pkgs,
  config,
  ...
}:
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    extensions = ps: [ ps.pgvector ];

    # Every client (Hivegent, Rauthy, the backups) is local, so serve the unix
    # socket only, and let each service role reach just its own database.
    settings.listen_addresses = lib.mkForce "";
    authentication = lib.mkForce ''
      local all      postgres peer map=postgres
      local sameuser all      peer
    '';
  };

  services.postgresqlBackup = {
    enable = true;
    compression = "zstd";
    databases = config.services.postgresql.ensureDatabases;
    # Each dump recreates its database with owners and grants, whose roles
    # `ensureUsers` provisions, so a restore needs no further steps.
    pgdumpOptions = "--clean --if-exists --create";
  };
}
