{ lib, ... }:
{
  # The MCP SDK only accepts HTTP issuers on `localhost` or `127.0.0.1`.
  virtualisation.vmVariant.services.hivegent.settings.mcp.base_url =
    lib.mkForce "http://localhost/mcp";
}
