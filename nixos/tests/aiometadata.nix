{ lib, pkgs, ... }:
{
  name = "aiometadata";
  meta.maintainers = with lib.maintainers; [ oynqr ];

  node.pkgsReadOnly = false;
  defaults.nixpkgs.config.allowUnfreePackages = [ "aiometadata" ];

  nodes.minimal.services.aiometadata.enable = true;

  nodes.machine = {
    environment.etc."aiometadata.env" = {
      mode = "0400";
      text = ''
        ADMIN_KEY=hunter2
        ADDON_PASSWORD=sesame
        BUILT_IN_TMDB_API_KEY='not a real key'
      '';
    };

    services.aiometadata = {
      enable = true;
      environmentFile = "/etc/aiometadata.env";
      settings = {
        PORT = 8080;
        HOST_NAME = "https://aiometadata.example.com";
        CUSTOM_DESCRIPTION_BLURB = "NixOS AIOMetadata";
        CATALOG_TTL = 3600;
        JIKAN_ENABLED = false;
      };
    };
  };

  testScript = ''
    import json
    import shlex

    start_all()

    minimal.wait_for_unit("aiometadata.service")
    minimal.wait_for_open_port(3232)
    minimal.succeed("curl --fail http://localhost:3232/health/live")
    minimal.wait_until_succeeds("curl --fail http://localhost:3232/health/ready")

    machine.wait_for_unit("aiometadata.service")
    machine.wait_for_open_port(8080)
    live = json.loads(machine.succeed("curl --fail http://localhost:8080/health/live"))
    assert live["version"] == "${pkgs.aiometadata.version}", live
    machine.wait_until_succeeds("curl --fail http://localhost:8080/health/ready")

    machine.succeed("curl --fail -L http://localhost:8080/configure | grep 'AIOMetadata Configuration'")
    config = json.loads(machine.succeed("curl --fail http://localhost:8080/api/config"))
    assert config["customDescriptionBlurb"] == "NixOS AIOMetadata", config
    assert config["catalogTTL"] == 3600, config
    assert config["hasBuiltInTmdb"], config
    assert not config["jikanEnabled"], config
    assert config["jellyfinBaseUrl"] == "https://aiometadata.example.com", config

    save = "curl --fail -H 'Content-Type: application/json' http://localhost:8080/api/config/save -d "
    body = {"config": {}, "password": "hunter2"}
    machine.fail(save + shlex.quote(json.dumps(body)))
    body["addonPassword"] = "sesame"
    saved = json.loads(machine.succeed(save + shlex.quote(json.dumps(body))))
    assert saved["installUrl"] == f"https://aiometadata.example.com/stremio/{saved['userUUID']}/manifest.json", saved

    for node in [minimal, machine]:
        node.succeed("test -f /var/lib/aiometadata/db.sqlite")
        node.fail("journalctl -u aiometadata.service | grep -E 'EROFS|EACCES'")
  '';
}
