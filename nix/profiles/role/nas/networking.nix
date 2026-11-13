{ inputs, ... }:
{
  config,
  ...
}:
let
  prefix = config.nas.ipv6Prefix;
  domain = config.homelab.workloads.domain;
  # All-zero WireGuard keys stand in for real ones
  noKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
in
{
  # Dual-stack Cilium with network policies, a WireGuard VPN for clients, one through a VPN provider for the apps
  # that want one, and the UniFi controller
  imports = [
    inputs.homelab-networking.nixosModules.cilium
    inputs.homelab-networking.nixosModules.privacy-vpn
    inputs.homelab-networking.nixosModules.client-vpn
    inputs.homelab-networking.nixosModules.unifi
    inputs.homelab-networking.nixosModules.routed-ippool
  ];
  config = {
    homelab.workloads.gatewayClassName = "cilium";
    # Plex reachable from the internet, through the router at the address of the home network
    homelab.kubernetes.submodules.instances.plex.config.kubernetes.resources.dNSEndpoints.plex-external.spec.endpoints =
      [
        {
          dnsName = "plex-external.${domain}";
          recordTTL = 300;
          recordType = "A";
          targets = [ "203.0.113.10" ];
        }
        {
          dnsName = "plex-external.${domain}";
          recordTTL = 300;
          recordType = "AAAA";
          targets = [ "${prefix}:0:44:0:14" ];
        }
      ];
    homelab = {
      cluster = {
        enableIPv4 = true;
        enableIPv6 = true;
        podCidr6 = "${prefix}:0:42::/96";
        svcCidr6 = "${prefix}:0:43::/112";
      };
      cilium = {
        enable = true;
        firewall.enable = true;
        lbIpBlock6.cidr = "${prefix}:0:44::/112";
        cidr-groups = {
          enable = true;
          localLANCIDR4 = "192.168.1.0/24";
          localLANCIDR6 = "2001:db8:1234:1::/64";
        };
        network-policies.enable = true;
      };
      routed-ippool = {
        enable = true;
        lbIpBlock6.cidr = "${prefix}:0:45::/112";
      };
      unifi = {
        enable = true;
        reservedIPs = [
          "10.45.0.3"
          "${prefix}:0:45:0:3"
        ];
      };
      plex = {
        reservedIPs = [
          "10.44.0.20"
          "${prefix}:0:44:0:14"
        ];
        tlsDomains = [
          "plex.${domain}"
          "plex-external.${domain}"
        ];
        allowIngress = [
          "local-lan"
          "internet"
        ];
      };
      client-vpn = {
        enable = true;
        groups.admins = {
          allowEgress = [
            "cluster"
            "local-lan"
          ];
          reservedIPs = [
            "10.45.0.2"
            "${prefix}:0:45:0:2"
          ];
          cidr4 = "10.16.189.0/24";
          gatewayIPv4 = "10.16.189.1/24";
          cidr6 = "fd00:1234:5678::/48";
          gatewayIPv6 = "fd00:1234:5678::1/48";
          # The public half of the key setup-secrets asks for
          gatewayPublicKey = noKey;
          peers.laptop = {
            enable = true;
            ipv4 = "10.16.189.2/32";
            ipv6 = "fd00:1234:5678::2/128";
            publicKey = noKey;
          };
        };
      };
      # The addresses ProtonVPN gives every client. The gateway is one of its servers
      privacy-vpn = {
        enable = true;
        clientIP4 = "10.2.0.2";
        clientIP6 = "2a07:b944::2:2";
        gatewayIP4 = "10.2.0.1";
        gatewayIP6 = "2a07:b944::2:1";
        gatewayAddress = "[2001:db8::10]:51820";
        gatewayPublicKey = noKey;
        extraPeerConfig.persistentKeepalive = 25;
      };
    };
  };
}
