{ lib, pkgs, ... }:
{
  name = "aiostreams";
  meta.maintainers = with lib.maintainers; [ oynqr ];

  nodes.minimal.services.aiostreams.enable = true;

  nodes.machine = {
    environment.etc."aiostreams.env" = {
      mode = "0400";
      text = ''
        SECRET_KEY=0000000000000000000000000000000000000000000000000000000000000000
        AIOSTREAMS_AUTH=admin:hunter2
      '';
    };

    services.aiostreams = {
      enable = true;
      environmentFile = "/etc/aiostreams.env";
      settings = {
        PORT = 8080;
        BASE_URL = "https://aiostreams.example.com";
        ADDON_NAME = "NixOS AIOStreams";
        JELLYFIN_ENABLED = false;
        TRUSTED_IPS = [ "loopback" ];
        ID_MAPPINGS_ENABLED = false;
        SCENE_MAPPINGS_ENABLED = false;
        ANIME_DB_LEVEL_OF_DETAIL = "none";
      };
    };
  };

  testScript = ''
    import json

    start_all()

    minimal.wait_for_unit("aiostreams.service")
    minimal.wait_for_open_port(3000)
    minimal.succeed("curl --fail http://localhost:3000/api/v1/health")
    key = minimal.succeed("cat /var/lib/aiostreams/secret-key")
    assert len(key) == 64, key
    minimal.systemctl("restart aiostreams.service")
    minimal.wait_for_open_port(3000)
    minimal.succeed("curl --fail http://localhost:3000/api/v1/health")
    assert minimal.succeed("cat /var/lib/aiostreams/secret-key") == key

    machine.wait_for_unit("aiostreams.service")
    machine.wait_for_open_port(8080)

    machine.succeed("curl --fail http://localhost:8080/api/v1/health")
    status = json.loads(machine.succeed("curl --fail http://localhost:8080/api/v1/status"))["data"]
    assert status["version"] == "${pkgs.aiostreams.version}", status["version"]
    assert status["settings"]["baseUrl"] == "https://aiostreams.example.com", status["settings"]
    assert status["settings"]["addonName"] == "NixOS AIOStreams", status["settings"]
    assert not status["settings"]["jellyfin"]["enabled"], status["settings"]

    machine.succeed(
        "curl --fail -c cookies -H 'Content-Type: application/json' -d '{\"username\":\"admin\",\"password\":\"hunter2\"}' http://localhost:8080/api/v1/auth/login"
    )
    ffprobe = json.loads(machine.succeed("curl --fail -b cookies http://localhost:8080/api/v1/dashboard/media-info"))["data"]["ffprobe"]
    assert ffprobe["version"] == "${pkgs.ffmpeg-headless.version}", ffprobe

    machine.succeed("test -f /var/lib/aiostreams/db.sqlite")
    machine.fail("test -e /var/lib/aiostreams/secret-key")
  '';
}
