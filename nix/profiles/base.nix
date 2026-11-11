{ self, inputs, ... }:
{ lib, config, ... }:
{
  # Every nixosConfiguration of the NAS
  imports = [
    inputs.sbfde.nixosModules.default
    inputs.setup-secrets.nixosModules.default
  ]
  ++ self.lib.importsApply [ ./all.nix ];
  config = {
    boot = {
      loader.timeout = 0;
      initrd.systemd.enable = true;
      loader.systemd-boot.configurationLimit = 120;
      lanzaboote.bootCounting.initialTries = 3;
    };
    # Secure Boot and a root partition encrypted with a key sealed to the TPM
    sbfde = {
      enable = true;
      enrollEmptyKey = true;
    };
    # Asks for the secrets at the first boot, the admin password among them
    setup-secrets = {
      autoSetup = true;
      users.enable = true;
    };
    environment.systemPackages = [ config.setup-secrets.script ];
    networking = {
      # Rejections make network troubleshooting a lot easier
      firewall.rejectPackets = true;
      useDHCP = true;
      useNetworkd = true;
      wireguard.useNetworkd = true;
    };
    services = {
      resolved.enable = true;
      avahi.enable = true;
      avahi.publish.enable = true;
      openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
        };
      };
    };
    nix = {
      settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
      gc.automatic = true;
      registry.nixpkgs.flake = inputs.nixpkgs;
    };
    users.mutableUsers = false;
    users.users.admin = {
      isNormalUser = true;
      uid = 1000;
      extraGroups = [ "wheel" ];
      hashedPasswordFile = lib.mkDefault "/etc/secrets.d/admin.pwhash";
      # Replace it with your own. k8sss also makes it a step-ca admin
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJVmz8ufrCNTAn5pxymr67Fa2t6LWKigtnTuLXwzw/52 admin@example.org"
      ];
    };
    security.sudo.wheelNeedsPassword = false;
  };
}
