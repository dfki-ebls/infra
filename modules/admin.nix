# Identity of the admin, from which modules/users.nix creates their account,
# shared with the installer image, which only needs the SSH keys for root.
{ ... }:
{
  custom.admin = {
    login = "mlenz";
    uid = 1000;
    name = "Mirko Lenz";
    mail = "mirko.lenz@dfki.de";
    sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFT0P6ZLB5QOtEdpPHCF0frL3WJEQQGEpMf2r010gYH3 mlenz@macbook"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPg/jZmSr0LiCm5FKAcF54UJXK8GNgDO4op0MiASNadb mlenz@iphone"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHTD8HTidTJM3RLmU+WW7tBlDz6L2x8zoHJhqzA6m3+B mlenz@1password"
    ];
  };
}
