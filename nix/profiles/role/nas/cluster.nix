{ inputs, ... }:
{
  pkgs,
  ...
}:
let
  inherit (inputs.homelab-shared.lib.setup-secrets) mkScript;
in
{
  # A single-node k3s cluster with step-ca for the users of the cluster, Let's Encrypt certificates and DNS records from external-dns,
  # both through the DNS provider INWX
  imports = [
    inputs.homelab-shared.nixosModules.cluster
    inputs.homelab-shared.nixosModules.k8sss
    inputs.homelab-shared.nixosModules.cert-manager
    inputs.homelab-networking.nixosModules.external-dns
  ];
  config = {
    homelab = {
      cluster.enable = true;
      k8sss.enable = true;
      cert-manager =
        let
          webhook-config = {
            provider = "inwx";
            secretName = "inwx-credentials";
          };
        in
        {
          acme-staging-issuer = { inherit webhook-config; };
          acme-production-issuer = { inherit webhook-config; };
        };
    };
    homelab.workloads.acmeProvider = "letsencrypt-production";
    homelab.kubernetes.submodules.instances.external-dns.config.kubernetes.resources.deployments.external-dns.spec.template.spec.containers.external-dns-libdns-webhook.env =
      {
        LIBDNS_PROVIDER_NAME.value = "inwx";
        INWX_USERNAME.valueFrom.secretKeyRef = {
          name = "inwx-credentials";
          key = "INWX_USERNAME";
        };
        INWX_PASSWORD.valueFrom.secretKeyRef = {
          name = "inwx-credentials";
          key = "INWX_PASSWORD";
        };
        LIBDNS_PROVIDER_CONFIG.value = ''
          {
            "Username": "$(INWX_USERNAME)",
            "Password": "$(INWX_PASSWORD)"
          }
        '';
      };
    # The INWX credentials, asked for once and stored in the cluster for both
    setup-secrets = {
      sources.INWX_USERNAME = {
        description = "INWX Username";
        cmd = mkScript pkgs "getKubeSecret cert-manager inwx-credentials username";
      };
      sources.INWX_PASSWORD = {
        description = "INWX Password";
        cmd = mkScript pkgs "getKubeSecret cert-manager inwx-credentials password";
      };
      destinations = [
        {
          logPrefix = "cert-manager (INWX Credentials)";
          requires = [
            "INWX_USERNAME"
            "INWX_PASSWORD"
          ];
          cmd = mkScript pkgs ''
            setKubeSecret cert-manager inwx-credentials \
              username "''${INWX_USERNAME:?}" \
              password "''${INWX_PASSWORD:?}"
          '';
        }
        {
          logPrefix = "external-dns (INWX Credentials)";
          requires = [
            "INWX_USERNAME"
            "INWX_PASSWORD"
          ];
          cmd = mkScript pkgs ''
            setKubeSecret external-dns inwx-credentials \
              INWX_USERNAME "''${INWX_USERNAME:?}" \
              INWX_PASSWORD "''${INWX_PASSWORD:?}"
          '';
        }
      ];
    };
  };
}
