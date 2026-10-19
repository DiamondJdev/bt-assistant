{ config, lib, pkgs, ... }:
let
  cfg = config.services.bt-assistant;
  runtime = with pkgs; [ stdenv.cc.cc.lib zlib portaudio libsndfile ];
in {
  options.services.bt-assistant = {
    enable = lib.mkEnableOption "BT private assistant";
    projectDir = lib.mkOption {
      type = lib.types.str;
      default = "/opt/bt-assistant";
      description = "Checkout with a preinstalled .venv. Keep it outside /home.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/bt.env";
      description = "Optional root-owned mode-0600 file with provider settings and secrets.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.bt = {};
    users.users.bt = { isSystemUser = true; group = "bt"; home = "/var/lib/bt"; };

    systemd.services.bt-assistant = {
      description = "BT private assistant";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" "ollama.service" ];
      after = [ "network-online.target" "ollama.service" ];
      path = with pkgs; [ ffmpeg ];
      environment = {
        BT_HOST = "127.0.0.1";
        BT_DB_PATH = "/var/lib/bt/bt.sqlite3";
        BT_VOICE = "1";
        BT_DEVUI = "0";
        BT_DEVELOPER_MODE = "0";
        HOME = "/var/lib/bt";
        XDG_CACHE_HOME = "/var/cache/bt";
        HF_HOME = "/var/cache/bt/huggingface";
        LD_LIBRARY_PATH = lib.makeLibraryPath runtime;
        PYTHONUNBUFFERED = "1";
      };
      serviceConfig = {
        User = "bt";
        Group = "bt";
        WorkingDirectory = cfg.projectDir;
        EnvironmentFile = "-${cfg.environmentFile}";
        ExecStart = "${cfg.projectDir}/.venv/bin/bt";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStartSec = 300;
        TimeoutStopSec = 45;
        StateDirectory = "bt";
        StateDirectoryMode = "0700";
        CacheDirectory = "bt";
        CacheDirectoryMode = "0700";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    systemd.services.bt-backup = {
      description = "BT transcript backup";
      after = [ "bt-assistant.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "bt";
        Group = "bt";
        StateDirectory = "bt";
        StateDirectoryMode = "0700";
        UMask = "0077";
        ExecStart = "${cfg.projectDir}/.venv/bin/python -m bt.backup /var/lib/bt/bt.sqlite3 /var/lib/bt/backups";
        WorkingDirectory = cfg.projectDir;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };
    systemd.timers.bt-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnCalendar = "daily"; Persistent = true; RandomizedDelaySec = "15m"; };
    };
  };
}
