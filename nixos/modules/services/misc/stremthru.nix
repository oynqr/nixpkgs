{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.stremthru;
  postgresql = lib.optional config.services.postgresql.enable "postgresql.target";
  toEnv =
    v:
    if lib.isBool v then
      lib.boolToString v
    else if lib.isList v then
      lib.concatStringsSep "," v
    else
      toString v;
in
{
  options.services.stremthru = {
    enable = lib.mkEnableOption "StremThru, a companion for Stremio";

    package = lib.mkPackageOption pkgs "stremthru" { };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open [](#opt-services.stremthru.settings.STREMTHRU_PORT) in the firewall.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.externalPath;
      default = null;
      example = "/run/secrets/stremthru.env";
      description = ''
        File containing secret environment variables as `KEY=value` lines. It
        is passed to the service as a systemd credential, so it only needs to
        be readable by root, and is sourced by a shell, so values containing
        whitespace or shell special characters must be single-quoted.

        It should contain {env}`STREMTHRU_AUTH` with a comma-separated list of
        `username:password` credentials. If it is not set, the instance is
        public and an admin account with a random password is generated on
        every start and printed to the journal.

        Other secrets such as {env}`STREMTHRU_AUTH_ADMIN`,
        {env}`STREMTHRU_STORE_AUTH`, {env}`STREMTHRU_VAULT_SECRET`, API keys
        and client secrets of integrations or a {env}`STREMTHRU_DATABASE_URI`
        or {env}`STREMTHRU_REDIS_URI` containing a password belong here as
        well.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType =
          with lib.types;
          attrsOf (
            nullOr (oneOf [
              bool
              int
              str
              (listOf str)
            ])
          );
        options = {
          STREMTHRU_PORT = lib.mkOption {
            type = lib.types.port;
            default = 8080;
            description = "Port on which StremThru listens on all interfaces.";
          };

          STREMTHRU_BASE_URL = lib.mkOption {
            type = lib.types.str;
            default = "http://localhost:${toString cfg.settings.STREMTHRU_PORT}";
            defaultText = lib.literalExpression ''"http://localhost:''${toString config.services.stremthru.settings.STREMTHRU_PORT}"'';
            example = "https://stremthru.example.com";
            description = "Public URL under which StremThru is reachable.";
          };

          STREMTHRU_DATABASE_URI = lib.mkOption {
            type = lib.types.str;
            default = "sqlite:///var/lib/stremthru/stremthru.db";
            example = "postgresql:///stremthru?host=/run/postgresql";
            description = ''
              Database connection URI. SQLite and PostgreSQL are supported.
              Other data is stored in {file}`/var/lib/stremthru`.
            '';
          };
        };
      };
      default = { };
      example = {
        STREMTHRU_BASE_URL = "https://stremthru.example.com";
        STREMTHRU_LOG_FORMAT = "text";
        STREMTHRU_FEATURE = [
          "-dmm_hashlist"
          "-imdb_title"
        ];
        STREMTHRU_PEER_URI = "-";
      };
      description = ''
        Environment variables used to configure StremThru, see
        <https://docs.stremthru.13377001.xyz/configuration/> for available
        settings and their defaults.

        Booleans are converted to `"true"` and `"false"`, lists to
        comma-separated strings and `null` values are omitted. Secrets must
        not be set here, use [](#opt-services.stremthru.environmentFile)
        instead.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.stremthru.settings.STREMTHRU_DATA_DIR = lib.mkDefault "/var/lib/stremthru";

    systemd.services.stremthru = {
      description = "StremThru";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ] ++ postgresql;
      after = [ "network-online.target" ] ++ postgresql;

      environment = lib.mapAttrs (_: toEnv) (lib.filterAttrs (_: v: v != null) cfg.settings);

      script = ''
        ${lib.optionalString (cfg.environmentFile != null) ''
          set -a
          . "$CREDENTIALS_DIRECTORY/environment"
          set +a
        ''}
        exec ${lib.getExe cfg.package}
      '';

      serviceConfig = {
        LoadCredential = lib.mkIf (cfg.environmentFile != null) "environment:${cfg.environmentFile}";
        Restart = "on-failure";
        RestartSec = 5;
        DynamicUser = true;
        StateDirectory = "stremthru";
        WorkingDirectory = "/var/lib/stremthru";
        UMask = "0077";
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        PrivateDevices = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.settings.STREMTHRU_PORT ];
  };

  meta.maintainers = with lib.maintainers; [ oynqr ];
}
