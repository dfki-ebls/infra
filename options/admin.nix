{ lib, ... }:
{
  options.custom.admin = {
    login = lib.mkOption {
      type = lib.types.str;
      description = "User and group name of the admin.";
    };
    uid = lib.mkOption {
      type = lib.types.int;
      description = "User and group ID of the admin.";
    };
    name = lib.mkOption {
      type = lib.types.str;
      description = "Display name of the admin.";
    };
    mail = lib.mkOption {
      type = lib.types.str;
      description = "Email address of the admin.";
    };
    sshKeys = lib.mkOption {
      type = with lib.types; listOf singleLineStr;
      description = "SSH public keys of the admin.";
    };
  };
}
