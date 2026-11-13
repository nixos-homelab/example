{ inputs, ... }:
{
  config,
  ...
}:
let
  # The pods mount the media library and the download directories from the NAS itself
  nfs = path: {
    server = "${config.networking.hostName}.${config.homelab.workloads.domain}";
    inherit path;
  };
in
{
  # The apps, on a homepage of links to them
  imports = [
    inputs.homelab-shared.nixosModules.postgresql
    inputs.homelab-shared.nixosModules.redis
    inputs.homelab-media.nixosModules.flood
    inputs.homelab-media.nixosModules.plex
    inputs.homelab-media.nixosModules.prowlarr
    inputs.homelab-media.nixosModules.radarr
    inputs.homelab-media.nixosModules.rtorrent
    inputs.homelab-media.nixosModules.sabnzbd
    inputs.homelab-media.nixosModules.sonarr
    inputs.homelab-monitoring.nixosModules.alloy
    inputs.homelab-monitoring.nixosModules.grafana
    inputs.homelab-monitoring.nixosModules.node-exporter
    inputs.homelab-monitoring.nixosModules.metrics-server
    inputs.homelab-monitoring.nixosModules.mimir
    inputs.homelab-monitoring.nixosModules.smartctl-exporter
    inputs.homelab-monitoring.nixosModules.zfs-exporter
    inputs.homelab-finance.nixosModules.actualbudget
    inputs.homelab-finance.nixosModules.ghostbudget
    inputs.homelab-finance.nixosModules.ghostfolio
    inputs.homelab-personal.nixosModules.syncthing
    inputs.homelab-personal.nixosModules.imap-backup
    inputs.homelab-personal.nixosModules.immich
  ];
  config.homelab = {
    homepage = {
      enable = true;
      sections.Media = {
        sort = 10;
        layout.style = "row";
        layout.columns = 3;
      };
      sections.Personal.sort = 20;
      sections.Finance.sort = 30;
      sections.Networking.sort = 50;
      sections.Monitoring.sort = 60;
    };
    redis.enable = true;
    postgresql.enable = true;
    syncthing.enable = true;
    immich.enable = true;
    imap-backup = {
      enable = true;
      accounts.mail = {
        username = "admin@example.org";
        mirrorMode = true;
        multiFetchSize = 10;
        server = "imap.example.org";
      };
    };
    plex = {
      enable = true;
      volumes."/mnt/media/movies".nfs = nfs "/mnt/media/movies";
      volumes."/mnt/media/tvshows".nfs = nfs "/mnt/media/tvshows";
    };
    actualbudget.enable = true;
    ghostfolio = {
      enable = true;
      importSchedule = "5,35 8-23 * * *";
      # The Sync ID of the budget, under Settings > Advanced in Actual, and which accounts in it go to which in Ghostfolio
      actualBudgetSyncId = "00000000-0000-0000-0000-000000000000";
      actualBudgetSyncMap = {
        Checking = "Checking";
        Brokerage = {
          ghostfolioName = "Brokerage";
          factor = 0.134228188;
        };
      };
    };
    flood = {
      enable = true;
      integrations.sonarr.settings.priority = 50;
      integrations.radarr.settings.priority = 50;
    };
    rtorrent = {
      enable = true;
      downloadsVolume.nfs = nfs "/mnt/cluster/torrents";
    };
    sabnzbd = {
      enable = true;
      downloadsVolume.nfs = nfs "/mnt/cluster/usenet";
    };
    sonarr = {
      enable = true;
      volumes."/mnt/media/tvshows".nfs = nfs "/mnt/media/tvshows";
    };
    radarr = {
      enable = true;
      volumes."/mnt/media/movies".nfs = nfs "/mnt/media/movies";
    };
    prowlarr.enable = true;
    metrics-server.enable = true;
    mimir.enable = true;
    grafana.enable = true;
    alloy.enable = true;
    node-exporter.enable = true;
    smartctl-exporter.enable = true;
    zfs-exporter.enable = true;
  };
}
