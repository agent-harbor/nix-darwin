{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.agent-harbor;
in
{
  options.services.agent-harbor = {
    enable = mkEnableOption "Agent Harbor";

    package = mkOption {
      type = types.package;
      default = pkgs.agent-harbor;
      defaultText = literalExpression "pkgs.agent-harbor";
      description = "The Agent Harbor package to use.";
    };

    snapshotDaemon = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable the privileged filesystem snapshot and sandbox daemon
          (ah-fs-snapshots-daemon) as a system launchd daemon running as root.
        '';
      };

      socketPath = mkOption {
        type = types.str;
        default = "/var/run/agent-harbor/ah-fs-snapshots-daemon";
        description = "Path to the UNIX domain socket for ah-fs-snapshots-daemon.";
      };

      logDir = mkOption {
        type = types.str;
        default = "/Library/Logs/AgentHarbor";
        description = "Directory for ah-fs-snapshots-daemon logs.";
      };

      logLevel = mkOption {
        type = types.enum [ "error" "warn" "info" "debug" "trace" ];
        default = "info";
        description = "Log level for ah-fs-snapshots-daemon.";
      };

      group = mkOption {
        type = types.str;
        default = "admin";
        description = ''
          Group allowed to access the daemon socket without sudo.
          On macOS workstations, developer user accounts belong to the `admin` group.
        '';
      };

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Extra arguments passed to ah-fs-snapshots-daemon.";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    environment.variables = mkIf cfg.snapshotDaemon.enable {
      AH_FS_SNAPSHOTS_DAEMON_SOCKET = cfg.snapshotDaemon.socketPath;
    };

    launchd.user.envVariables = mkIf cfg.snapshotDaemon.enable {
      AH_FS_SNAPSHOTS_DAEMON_SOCKET = cfg.snapshotDaemon.socketPath;
    };

    system.activationScripts.launchd.text = mkIf cfg.snapshotDaemon.enable (mkBefore ''
      echo >&2 "setting up Agent Harbor directories..."
      mkdir -p -m 0775 "$(dirname "${cfg.snapshotDaemon.socketPath}")"
      chown root:${cfg.snapshotDaemon.group} "$(dirname "${cfg.snapshotDaemon.socketPath}")"
      chmod 0775 "$(dirname "${cfg.snapshotDaemon.socketPath}")"

      mkdir -p -m 0755 "${cfg.snapshotDaemon.logDir}"
      chown root:wheel "${cfg.snapshotDaemon.logDir}"
      chmod 0755 "${cfg.snapshotDaemon.logDir}"
    '');

    launchd.daemons.ah-fs-snapshots-daemon = mkIf cfg.snapshotDaemon.enable {
      command = lib.concatStringsSep " " (
        [
          "${cfg.package}/bin/ah-fs-snapshots-daemon"
          "--log-dir" cfg.snapshotDaemon.logDir
          "--log-level" cfg.snapshotDaemon.logLevel
          "start"
          "--socket-path" cfg.snapshotDaemon.socketPath
        ]
        ++ cfg.snapshotDaemon.extraArgs
      );
      serviceConfig = {
        Label = "com.agentharbor.daemon";
        UserName = "root";
        GroupName = cfg.snapshotDaemon.group;
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
        };
        StandardOutPath = "${cfg.snapshotDaemon.logDir}/daemon.log";
        StandardErrorPath = "${cfg.snapshotDaemon.logDir}/daemon-error.log";
      };
    };
  };
}
