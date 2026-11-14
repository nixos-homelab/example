{ inputs, ... }:
{
  lib,
  config,
  ...
}:
let
  # The user the pods run as and the owner of their data on the pools
  cluster = 900;
  admin = config.users.users.admin.uid;
  users = config.users.groups.users.gid;
in
{
  # k3s and the data of the apps on the cluster pool, which the pods mount over NFS, as they do the media library
  imports = [ inputs.homelab-storage.nixosModules.nfs-provisioner ];
  config = {
    users = {
      users.cluster = {
        isSystemUser = true;
        uid = cluster;
        group = "cluster";
      };
      groups.cluster.gid = cluster;
    };
    homelab.workloads.securityContext = {
      runAsUser = cluster;
      runAsGroup = cluster;
      supplementalGroups = [ users ];
    };
    homelab = {
      k3s.dataDir = "/mnt/cluster/k3s";
      nfs-provisioner = {
        enable = true;
        path = "/mnt/cluster/data";
        mountpointOwnership = {
          uid = cluster;
          gid = cluster;
        };
      };
    };
    # Without the pool mounted (a key that didn't load) k3s would start a new cluster on the root filesystem
    systemd.services.k3s.unitConfig.AssertPathIsMountPoint = config.homelab.k3s.dataDir;
    services.nfs.server = {
      enable = true;
      # The NAS mounts the exports itself, through an FQDN that /etc/hosts maps to 127.0.0.2
      exports =
        let
          export = path: options: "${path} 127.0.0.0/8(${options})\n";
          cluster' = "rw,root_squash,anonuid=${toString cluster},anongid=${toString cluster}";
          admin' = "rw,all_squash,anonuid=${toString admin},anongid=${toString users}";
        in
        lib.concatStrings [
          (export config.homelab.nfs-provisioner.path cluster')
          (export "/mnt/cluster/usenet" cluster')
          (export "/mnt/cluster/torrents" cluster')
          (export "/mnt/media/tvshows" admin')
          (export "/mnt/media/movies" admin')
        ];
    };
    # At shutdown the pods stop before the NFS mounts and those before the server, or the NFS client hangs waiting for
    # a stopped server, and the shutdown with it
    systemd.slices.kubepods = {
      # kubelet creates the slice as a transient unit
      overrideStrategy = "asDropin";
      after = [
        "remote-fs.target"
        "nfs-server.service"
      ];
    };
    systemd.services.nfs-server.before = [ "remote-fs-pre.target" ];
  };
}
