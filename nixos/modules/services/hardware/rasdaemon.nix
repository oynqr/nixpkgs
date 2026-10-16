{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let

  cfg = config.hardware.rasdaemon;

  labelsFile = "/etc/ras/dimm_labels.d/labels";
  configFile = "/etc/sysconfig/rasdaemon";

  registerLabels = cfg.labels != "" || cfg.vendor != null || cfg.model != null;
in
{
  imports = [
    (lib.mkRemovedOptionModule [ "hardware" "rasdaemon" "mainboard" ] ''
      rasdaemon >= 1.0.0 no longer reads /etc/ras/mainboard.
      Use hardware.rasdaemon.vendor and hardware.rasdaemon.model instead.
    '')
  ];

  meta = {
    inherit (pkgs.rasdaemon.meta) maintainers;
  };

  options.hardware.rasdaemon = {

    enable = lib.mkEnableOption "RAS logging daemon";

    package = lib.mkPackageOption pkgs "rasdaemon" { };

    record = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Record events via sqlite3, required for {command}`ras-mc-ctl`.";
    };

    vendor = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "ASRock";
      description = ''
        Mainboard vendor used to look up DIMM labels, passed to
        {command}`ras-mc-ctl dimm` as `--vendor`. When `null`, the value from
        {file}`/sys/class/dmi/id/board_vendor` is used.
      '';
    };

    model = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "B450M Pro4";
      description = ''
        Mainboard model used to look up DIMM labels, passed to
        {command}`ras-mc-ctl dimm` as `--model`. When `null`, the value from
        {file}`/sys/class/dmi/id/board_name` is used.
      '';
    };

    labels = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Memory module label descriptions, written to {file}`${labelsFile}`
        and registered on startup via {command}`ras-mc-ctl dimm --register-labels`.
      '';
      example = ''
        # vendor and model may be shown by `ras-mc-ctl dimm --mainboard`
        vendor: ASRock
          product: To Be Filled By O.E.M.
          model: B450M Pro4
            # these labels are names for the motherboard slots
            # the numbers may be shown by `ras-mc-ctl dimm --error-count`
            # they are mc.csrow.channel
            DDR4_A1: 0.2.0;  DDR4_B1: 0.2.1;
            DDR4_A2: 0.3.0;  DDR4_B2: 0.3.1;
      '';
    };

    config = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        rasdaemon configuration, currently only used for CE PFA.
        See the comments in {file}`''${pkgs.rasdaemon}/etc/sysconfig/rasdaemon` for details.
      '';
      example = ''
        # defaults from included config
        PAGE_CE_REFRESH_CYCLE="24h"
        PAGE_CE_THRESHOLD="50"
        PAGE_CE_ACTION="soft"
      '';
    };

    extraModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra kernel modules to load.";
      example = [ "i7core_edac" ];
    };

    testing = lib.mkEnableOption "error injection infrastructure";
  };

  config = lib.mkIf cfg.enable {

    environment.etc = {
      # TODO, handle multiple cfg.labels.brand = " ";
      "ras/dimm_labels.d/labels" = {
        enable = cfg.labels != "";
        text = cfg.labels;
      };
      "sysconfig/rasdaemon" = {
        enable = cfg.config != "";
        text = cfg.config;
      };
    };
    environment.systemPackages = [
      cfg.package
    ]
    ++ lib.optionals cfg.testing (
      with pkgs.error-inject;
      [
        edac-inject
        mce-inject
        aer-inject
      ]
    );

    boot.initrd.kernelModules =
      cfg.extraModules
      ++ lib.optionals cfg.testing [
        "edac_core"
        "amd64_edac"
        "i7core_edac"
        "mce-inject"
        "aer-inject"
      ];

    boot.kernelPatches = lib.optionals cfg.testing [
      {
        name = "rasdaemon-tests";
        patch = null;
        extraConfig = ''
          EDAC_DEBUG y
          X86_MCE_INJECT y

          PCIEPORTBUS y
          PCIEAER y
          PCIEAER_INJECT y
        '';
      }
    ];

    # i tried to set up a group for this
    # but rasdaemon needs higher permissions?
    # `rasdaemon: Can't locate a mounted debugfs`

    # most of this taken from src/misc/
    systemd.services = {
      rasdaemon = {
        description = "the RAS logging daemon";
        documentation = [ "man:rasdaemon(1)" ];
        wantedBy = [ "multi-user.target" ];

        unitConfig.RequiresMountsFor = "/sys/kernel/debug";
        restartTriggers = lib.optional (
          cfg.config != ""
        ) config.environment.etc."sysconfig/rasdaemon".source;
        serviceConfig = {
          EnvironmentFile = lib.mkIf (cfg.config != "") configFile;
          StateDirectory = lib.optionalString cfg.record "rasdaemon";
          ExecStart = utils.escapeSystemdExecArgs (
            [
              "${cfg.package}/bin/rasdaemon"
              "--foreground"
            ]
            ++ lib.optional cfg.record "--record"
          );
          ExecStop = "${cfg.package}/bin/rasdaemon --disable";
          Restart = "on-abort";

          # src/misc/rasdaemon.service.in shows this:
          # ExecStartPost = ${cfg.package}/bin/rasdaemon --enable
          # but that results in unpredictable existence of the database
          # and everything seems to be enabled without this...
        };
      };
      ras-mc-ctl = lib.mkIf registerLabels {
        description = "register DIMM labels on startup";
        documentation = [ "man:ras-mc-ctl(8)" ];
        wantedBy = [ "multi-user.target" ];
        restartTriggers = lib.optional (
          cfg.labels != ""
        ) config.environment.etc."ras/dimm_labels.d/labels".source;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = utils.escapeSystemdExecArgs (
            [ "${cfg.package}/bin/ras-mc-ctl" ]
            ++ lib.optionals (cfg.config != "") [
              "--config"
              configFile
            ]
            ++ [
              "dimm"
              "--register-labels"
            ]
            ++ lib.optionals (cfg.labels != "") [
              "--labeldb"
              labelsFile
            ]
            ++ lib.optionals (cfg.vendor != null) [
              "--vendor"
              cfg.vendor
            ]
            ++ lib.optionals (cfg.model != null) [
              "--model"
              cfg.model
            ]
          );
        };
      };
    };
  };
}
