{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.aiometadata;
  redis = config.services.redis.servers.aiometadata;
  postgresql = lib.optional config.services.postgresql.enable "postgresql.target";
  redisService = lib.optional cfg.redis.createLocally "redis-aiometadata.service";
  settingsFormat = pkgs.formats.json { };
  toEnv =
    v:
    if lib.isBool v then
      lib.boolToString v
    else if lib.isList v || lib.isAttrs v then
      builtins.toJSON v
    else if lib.isPath v then
      "${v}"
    else
      toString v;
in
{
  options.services.aiometadata = {
    enable = lib.mkEnableOption "AIOMetadata, a metadata provider addon for Stremio";

    package = lib.mkPackageOption pkgs "aiometadata" { };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open [](#opt-services.aiometadata.settings.PORT) in the firewall.";
    };

    redis.createLocally = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to set up a local Redis server and connect to it over a unix
        socket. If disabled, {env}`REDIS_URL` must point to a Redis 8.0 or newer
        server.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.externalPath;
      default = null;
      example = "/run/secrets/aiometadata.env";
      description = ''
        File containing secret environment variables as `KEY=value` lines. It
        is passed to the service as a systemd credential, so it only needs to
        be readable by root, and is sourced by a shell, so values containing
        whitespace or shell special characters must be single-quoted.

        Secrets such as {env}`ADMIN_KEY`, {env}`ADDON_PASSWORD`,
        {env}`BUILT_IN_TMDB_API_KEY` and the other API keys, OAuth client
        secrets like {env}`TRAKT_CLIENT_SECRET`, {env}`MOVIELENS_CRED_KEY` or
        a {env}`DATABASE_URI` or {env}`REDIS_URL` containing a password belong
        here. Note that {env}`TMDB_API_KEY`, {env}`TVDB_API_KEY` and similar
        keys without the `BUILT_IN_` prefix are published to every visitor of
        the configuration page.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = lib.types.attrsOf settingsFormat.type;
        options = {
          PORT = lib.mkOption {
            type = lib.types.port;
            default = 3232;
            description = "Port on which AIOMetadata listens on all interfaces.";
          };

          HOST_NAME = lib.mkOption {
            type = lib.types.str;
            default = "http://localhost:${toString cfg.settings.PORT}";
            defaultText = lib.literalExpression ''"http://localhost:''${toString config.services.aiometadata.settings.PORT}"'';
            example = "https://aiometadata.example.com";
            description = "Public URL under which AIOMetadata is reachable.";
          };

          DATABASE_URI = lib.mkOption {
            type = lib.types.str;
            default = "sqlite:///var/lib/aiometadata/db.sqlite";
            example = "postgresql:///aiometadata?host=/run/postgresql";
            description = ''
              Database connection URI. SQLite and PostgreSQL are supported.
              Other data is stored in {file}`/var/lib/aiometadata/addon/data`.
            '';
          };
        };
      };
      default = { };
      example = {
        HOST_NAME = "https://aiometadata.example.com";
        ADDON_NAME_SUFFIX = "| My Server";
        ENABLE_BUILTIN_POSTER_CACHE = true;
        CACHE_WARMUP_MODE = "comprehensive";
      };
      description = ''
        Environment variables used to configure AIOMetadata, see
        <https://github.com/cedya77/aiometadata/blob/dev/docs/ENVIRONMENT_VARIABLES.md>
        for available settings and their defaults.

        Settings set here are locked in the dashboard. Booleans are converted
        to `"true"` and `"false"`, lists and attribute sets to JSON and `null`
        values are omitted. Secrets must not be set here, use
        [](#opt-services.aiometadata.environmentFile) instead.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.aiometadata.settings = {
      POSTER_CACHE_DIR = lib.mkDefault "/var/cache/aiometadata";
      REDIS_URL = lib.mkIf cfg.redis.createLocally redis.unixSocket;
    };

    services.redis.servers.aiometadata.enable = lib.mkIf cfg.redis.createLocally true;

    systemd.services.aiometadata = {
      description = "AIOMetadata";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ] ++ postgresql;
      requires = redisService;
      after = [ "network-online.target" ] ++ postgresql ++ redisService;

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
        DynamicUser = true;
        SupplementaryGroups = lib.mkIf cfg.redis.createLocally [ redis.group ];
        StateDirectory = "aiometadata";
        CacheDirectory = "aiometadata";
        WorkingDirectory = "/var/lib/aiometadata";
        UMask = "0077";
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        LockPersonality = true;
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

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.settings.PORT ];
  };

  meta.maintainers = with lib.maintainers; [ oynqr ];
}
