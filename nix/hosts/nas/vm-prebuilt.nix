{ self, ... }:
{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cluster = "cluster:cluster";
  admin = "admin:users";
  # The pools of the NAS and the owners of their datasets
  pools = {
    cluster = {
      size = 32768;
      datasets = {
        k3s = "root:root";
        data = cluster;
        torrents = cluster;
        usenet = cluster;
      };
    };
    media = {
      size = 2048;
      datasets = {
        movies = admin;
        tvshows = admin;
      };
    };
  };
  disk = pool: "/dev/disk/by-id/virtio-${pool}";
  # The properties ZED's list cacher writes for zfs-mount-generator (history_event-zfs-list-cacher.sh)
  listCacheProps = lib.concatStringsSep "," (
    [
      "name"
      "mountpoint"
      "canmount"
      "atime"
      "relatime"
      "devices"
      "exec"
      "readonly"
      "setuid"
      "nbmand"
      "encroot"
      "keylocation"
    ]
    ++ map (p: "org.openzfs.systemd:${p}") [
      "requires"
      "requires-mounts-for"
      "before"
      "after"
      "wanted-by"
      "required-by"
      "nofail"
      "ignore"
    ]
  );
  disks = map (pool: "${utils.escapeSystemdPath (disk pool)}.device") (lib.attrNames pools);
  # The setup-secrets destination of openzfs that seals the key of a pool to the TPM in the credstore
  sealKey =
    pool:
    (lib.findFirst (
      dest: dest.requires == [ "ZFS_ENCRYPTION_KEY_${pool}" ]
    ) (throw "no setup-secrets destination for the key of ${pool}") config.setup-secrets.destinations)
    .cmd;
in
{
  # The NAS in a VM, from a prebuilt disk image
  imports = self.lib.importsApply [
    ../../profiles/role/nas
    ../../profiles/target/vm-prebuilt.nix
  ];
  config = {
    networking.hostName = "nas-prebuilt";
    networking.domain = "prebuilt.example.org";
    homelab.workloads.domain = "prebuilt.example.org";
    # Measured with setup-secrets done and every workload up: 6.1 GiB used, 1.7 GiB available
    virtualisation.memorySize = 8 * 1024;
    # The ARC grows into nearly all of the VM's memory by default, which the host then has to back
    boot.kernelParams = [ "zfs.zfs_arc_max=${toString (512 * 1024 * 1024)}" ];
    virtualisation.emptyDiskImages = lib.mapAttrsToList (pool: spec: {
      inherit (spec) size;
      driveConfig.deviceExtraOpts.serial = pool;
    }) pools;
    # The pools of the NAS are made at the install. These are made on the blank disks at the first boot with
    # Secure Boot on, whose PCR 7 the keys are sealed to, before anything mounts or writes below them
    systemd.services.vm-zfs-pools = {
      description = "Create the ZFS pools on the VM's blank disks";
      unitConfig = {
        DefaultDependencies = false;
        ConditionSecurity = "uefi-secureboot";
        ConditionPathExists = "!/etc/zfs/zpool.cache";
      };
      requires = disks;
      after = [ "tpm2.target" ] ++ disks;
      before = [
        "zfs-import-cache.service"
        "local-fs.target"
      ];
      wantedBy = [ "local-fs.target" ];
      path = [
        config.boot.zfs.package
        pkgs.coreutils
      ];
      serviceConfig.Type = "oneshot";
      script = ''
        key=$(mktemp -p /run)
        trap 'rm -f "$key"' EXIT
      ''
      + lib.concatStrings (
        lib.mapAttrsToList (pool: spec: ''
          od -An -tx1 -N32 /dev/urandom | tr -d ' \n' >"$key"
          zpool create -o ashift=12 -O encryption=on -O keyformat=hex -O keylocation="file://$key" \
            -O mountpoint=/mnt/${pool} ${pool} ${disk pool}
          zfs set keylocation=prompt ${pool}
          ZFS_ENCRYPTION_KEY_${pool}=$(<"$key") ${sealKey pool}
          ${lib.concatStrings (
            lib.mapAttrsToList (dataset: owner: ''
              zfs create ${pool}/${dataset}
              chown ${owner} /mnt/${pool}/${dataset}
            '') spec.datasets
          )}
          # ZED isn't running yet, so an install writes the cache the mounts at the next boot come from
          mkdir -p /etc/zfs/zfs-list.cache
          zfs list -H -t filesystem -o ${listCacheProps} -r ${pool} | sort >/etc/zfs/zfs-list.cache/${pool}
        '') pools
      );
    };
  };
}
