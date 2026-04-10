{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.boot.kexec;
in
{
  options.boot.kexec = {
    enable = lib.mkEnableOption "kexec" // {
      default = lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.kexec-tools;
      defaultText = lib.literalExpression "lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.kexec-tools";
    };

    luksUnlockCredential = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a LUKS keyfile to pass to the kexec'd initrd, so that the
        disk can be unlocked automatically without re-entering a passphrase.

        The file must already be enrolled as a LUKS key slot on the encrypted
        device (e.g. via <command>cryptsetup luksAddKey</command>), and the
        corresponding <option>boot.initrd.luks.devices.&lt;name&gt;.keyFile</option>
        must be set to the same in-initrd path that this credential is
        spliced in as (by default <literal>/kexec-luks.key</literal>).
      '';
    };

    luksUnlockCredentialInitrdPath = lib.mkOption {
      type = lib.types.str;
      default = "/kexec-luks.key";
      description = ''
        The absolute path at which the LUKS keyfile will appear inside the
        initrd.  Must match the value of
        <option>boot.initrd.luks.devices.&lt;name&gt;.keyFile</option> for
        every device that should be unlocked automatically.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.kexec-tools ];

    systemd.services.prepare-kexec = {
      description = "Preparation for kexec";
      wantedBy = [ "kexec.target" ];
      before = [ "systemd-kexec.service" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
      }
      // lib.optionalAttrs (cfg.luksUnlockCredential != null) {
        LoadCredential = "luks.key:${cfg.luksUnlockCredential}";
      };
      path = [
        pkgs.kexec-tools
        pkgs.cpio
        pkgs.gzip
      ];
      script =
        let
          keyInInitrd = lib.removePrefix "/" cfg.luksUnlockCredentialInitrdPath;
        in
        ''
          # Don't load the current system profile if we already have a kernel loaded
          if [[ 1 = "$(</sys/kernel/kexec_loaded)" ]] ; then
            echo "kexec kernel has already been loaded, prepare-kexec skipped"
            exit 0
          fi

          p=$(readlink -f /nix/var/nix/profiles/system)
          if ! [[ -d $p ]]; then
            echo "Could not find system profile for prepare-kexec"
            exit 1
          fi

          ${lib.optionalString (cfg.luksUnlockCredential != null) ''
            # Build a small supplemental initrd in RAM that contains only the
            # LUKS keyfile.
            WORK=$(mktemp -d /dev/shm/kexec-initrd.XXXXXXXXXX)
            trap 'find "$WORK" -type f -exec shred -u {} +; rm -rf "$WORK"' EXIT

            # Reproduce the directory structure the initrd expects.
            mkdir -p "$WORK/$(dirname "${keyInInitrd}")"
            cp "$CREDENTIALS_DIRECTORY/luks.key" "$WORK/${keyInInitrd}"
            chmod 400 "$WORK/${keyInInitrd}"

            # Pack the keyfile into a cpio archive and concatenate it after
            # the system initrd.
            COMBINED="$WORK/initrd"
            cat "$p/initrd" > "$COMBINED"
            ( cd "$WORK" && echo "${keyInInitrd}" | cpio -o -H newc -R 0:0 ) \
              | gzip -1 >> "$COMBINED"

            echo "Loading NixOS system via kexec (with LUKS credential)."
            exec kexec --load "$p/kernel" --initrd="$COMBINED" \
              --append="$(cat "$p/kernel-params") init=$p/init"
          ''}

          ${lib.optionalString (cfg.luksUnlockCredential == null) ''
            echo "Loading NixOS system via kexec."
            exec kexec --load "$p/kernel" --initrd="$p/initrd" \
              --append="$(cat "$p/kernel-params") init=$p/init"
          ''}
        '';
    };
  };
}
