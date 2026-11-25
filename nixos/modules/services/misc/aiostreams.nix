{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.aiostreams;
  postgresql = lib.optional config.services.postgresql.enable "postgresql.target";
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
  options.services.aiostreams = {
    enable = lib.mkEnableOption "AIOStreams, a Stremio addon aggregator";

    package = lib.mkPackageOption pkgs "aiostreams" { };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to open [](#opt-services.aiostreams.settings.PORT) in the
        firewall. Ports of optional listeners such as {env}`SHARES_NFS_PORT`
        must be opened separately.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.externalPath;
      default = null;
      example = "/run/secrets/aiostreams.env";
      description = ''
        File containing secret environment variables as `KEY=value` lines. It
        is passed to the service as a systemd credential, so it only needs to
        be readable by root, and is sourced by a shell, so values containing
        whitespace or shell special characters must be single-quoted.

        It may contain {env}`SECRET_KEY`, a string of 64 hexadecimal characters
        that can be generated with `openssl rand -hex 32`. If it is not set, a
        key is generated on first start and stored in
        {file}`/var/lib/aiostreams/secret-key`. The key must not change after
        the first start, or existing user configurations cannot be decrypted.

        Other secrets such as {env}`AIOSTREAMS_AUTH`, {env}`CONFIG_ACCESS_KEY`,
        {env}`TMDB_API_KEY` or a {env}`DATABASE_URI` containing a password
        belong here as well.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = lib.types.attrsOf settingsFormat.type;
        options = {
          PORT = lib.mkOption {
            type = lib.types.port;
            default = 3000;
            description = "Port on which AIOStreams listens on all interfaces.";
          };

          BASE_URL = lib.mkOption {
            type = lib.types.str;
            default = "http://localhost:${toString cfg.settings.PORT}";
            defaultText = lib.literalExpression ''"http://localhost:''${toString config.services.aiostreams.settings.PORT}"'';
            example = "https://aiostreams.example.com";
            description = "Public URL under which AIOStreams is reachable.";
          };

          DATABASE_URI = lib.mkOption {
            type = lib.types.str;
            default = "sqlite:///var/lib/aiostreams/db.sqlite";
            example = "postgresql:///aiostreams?host=/run/postgresql";
            description = ''
              Database connection URI. SQLite and PostgreSQL are supported.
              Data files other than the database are stored next to an SQLite
              database, or in {file}`/var/lib/aiostreams/data` otherwise.
            '';
          };
        };
      };
      default = { };
      example = {
        BASE_URL = "https://aiostreams.example.com";
        ADDON_NAME = "My AIOStreams";
        LOG_FORMAT = "text";
        AIOSTREAMS_AUTH_REQUIRED = true;
        TRUSTED_IPS = [
          "loopback"
          "10.0.0.0/8"
        ];
      };
      description = ''
        Environment variables used to configure AIOStreams, see
        <https://aiostreams.org/configuration/environment-variables> for
        available settings and their defaults.

        Settings set here are locked in the web interface. Booleans are
        converted to `"true"` and `"false"`, lists and attribute sets to JSON
        and `null` values are omitted. Secrets must not be set here, use
        [](#opt-services.aiostreams.environmentFile) instead.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.aiostreams.settings = {
      DISK_CACHE_DIR = lib.mkDefault "/var/cache/aiostreams";
      FFPROBE_PATH = lib.mkDefault (lib.getExe' pkgs.ffmpeg-headless "ffprobe");
    };

    systemd.services.aiostreams = {
      description = "AIOStreams";
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
        if [ -z "''${SECRET_KEY:-}" ]; then
          if [ ! -s "$STATE_DIRECTORY/secret-key" ]; then
            head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$STATE_DIRECTORY/secret-key"
          fi
          SECRET_KEY=$(< "$STATE_DIRECTORY/secret-key")
          export SECRET_KEY
        fi
        exec ${lib.getExe cfg.package}
      '';

      serviceConfig = {
        LoadCredential = lib.mkIf (cfg.environmentFile != null) "environment:${cfg.environmentFile}";
        Restart = "on-failure";
        DynamicUser = true;
        StateDirectory = "aiostreams";
        CacheDirectory = "aiostreams";
        WorkingDirectory = "/var/lib/aiostreams";
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
