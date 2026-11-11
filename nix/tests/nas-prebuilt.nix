{ lib, hostPkgs, ... }:
let
  client = {
    nixpkgs.hostPlatform = hostPkgs.stdenv.hostPlatform.system;
    environment.systemPackages = [ hostPkgs.netcat ];
  };
in
{
  # The host firewall's LAN is the test VLAN's lower half: lan and the nas get .1 and .2, outside sits above it
  nodes.nas.homelab.cilium.cidr-groups.localLANCIDR4 = lib.mkForce "192.168.1.0/25";
  nodes.lan = lib.mkMerge [
    client
    # For the pods allowed to reach the LAN
    { networking.firewall.allowedTCPPorts = [ 8000 ]; }
  ];
  nodes.outside = lib.mkMerge [
    client
    {
      networking.interfaces.eth1.ipv4.addresses = lib.mkForce [
        {
          address = "192.168.1.200";
          prefixLength = 24;
        }
      ];
    }
  ];
}
