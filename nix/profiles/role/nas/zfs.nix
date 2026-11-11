{ inputs, ... }:
{
  lib,
  pkgs,
  ...
}:
let
  pools = [
    "cluster"
    "media"
  ];
  pushoverCreds = "/etc/secrets.d/pushover-credentials.env";
in
{
  # Two encrypted pools, made at the install: cluster for k3s and the data of the apps, media for the media library.
  # Their keys are sealed to the TPM, so they unlock and mount at boot
  imports = [ inputs.openzfs.nixosModules.default ];
  config = {
    openzfs = {
      enable = true;
      pools = lib.genAttrs pools (_: {
        autoDecrypt = true;
        autoMount = true;
      });
      # ZED notifies through Pushover, with the credentials setup-secrets asks for
      zed.literalSettings = ''
        . "${pushoverCreds}"
      '';
    };
    environment.systemPackages = [ pkgs.zfs ];
    # Yours: head -c 8 /etc/machine-id
    networking.hostId = "61cd2f29";
    systemd.timers = lib.mergeAttrsList (
      map (pool: {
        "zfs-scrub-monthly@${pool}" = {
          overrideStrategy = "asDropin";
          wantedBy = [ "timers.target" ];
        };
        "zfs-trim-weekly@${pool}" = {
          overrideStrategy = "asDropin";
          wantedBy = [ "timers.target" ];
        };
      }) pools
    );
    setup-secrets = {
      sources = lib.genAttrs [ "ZED_PUSHOVER_USER" "ZED_PUSHOVER_TOKEN" ] (name: {
        description = "ZFS Event Daemon ${name}";
        cmd = ''
          source "${pushoverCreds}"
          printf "%s" "''$${name}"
        '';
      });
      destinations = [
        {
          logPrefix = "ZFS Event Daemon Pushover credentials";
          requires = [
            "ZED_PUSHOVER_USER"
            "ZED_PUSHOVER_TOKEN"
          ];
          cmd = ''
            umask 077
            printf "ZED_PUSHOVER_USER=%q\nZED_PUSHOVER_TOKEN=%q\n" "$ZED_PUSHOVER_USER" "$ZED_PUSHOVER_TOKEN" >"${pushoverCreds}"
          '';
        }
      ];
    };
  };
}
