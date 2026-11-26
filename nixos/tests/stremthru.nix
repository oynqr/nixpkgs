{ lib, pkgs, ... }:
let
  ipChecker = pkgs.runCommand "checkip-cert" { nativeBuildInputs = [ pkgs.openssl ]; } ''
    mkdir $out
    openssl req -x509 -newkey rsa:2048 -nodes -days 36500 -subj /CN=checkip.amazonaws.com \
      -addext subjectAltName=DNS:checkip.amazonaws.com -keyout $out/key.pem -out $out/cert.pem
  '';
in
{
  name = "stremthru";
  meta.maintainers = with lib.maintainers; [ oynqr ];

  defaults = {
    networking.hosts."127.0.0.1" = [ "checkip.amazonaws.com" ];
    security.pki.certificateFiles = [ "${ipChecker}/cert.pem" ];
    services.nginx = {
      enable = true;
      virtualHosts."checkip.amazonaws.com" = {
        onlySSL = true;
        sslCertificate = "${ipChecker}/cert.pem";
        sslCertificateKey = "${ipChecker}/key.pem";
        locations."/".return = "200 192.0.2.1";
      };
    };
    systemd.services.stremthru.after = [ "nginx.service" ];
  };

  nodes.minimal.services.stremthru.enable = true;

  nodes.machine = {
    environment.etc."stremthru.env" = {
      mode = "0400";
      text = ''
        STREMTHRU_AUTH='admin:hunter 2'
      '';
    };

    services.stremthru = {
      enable = true;
      environmentFile = "/etc/stremthru.env";
      settings = {
        STREMTHRU_PORT = 9090;
        STREMTHRU_BASE_URL = "https://stremthru.example.com";
        STREMTHRU_STREMIO_LOCKED = true;
        STREMTHRU_PEER_URI = "-";
        STREMTHRU_FEATURE = [
          "-dmm_hashlist"
          "-imdb_title"
        ];
      };
    };
  };

  testScript = ''
    import json
    import shlex

    start_all()

    minimal.wait_for_unit("stremthru.service")
    minimal.wait_for_open_port(8080)
    minimal.succeed("curl --fail http://localhost:8080/v0/health")
    minimal.succeed("journalctl -u stremthru.service | grep 'Auto Generated'")

    machine.wait_for_unit("stremthru.service")
    machine.wait_for_open_port(9090)
    machine.succeed("curl --fail http://localhost:9090/v0/health")
    machine.succeed("curl --fail http://localhost:9090/dash/ | grep 'StremThru</title>'")

    signin = "curl --fail -c cookies -H 'Content-Type: application/json' http://localhost:9090/dash/api/auth/signin -d "
    body = {"user": "admin", "password": "hunter"}
    machine.fail(signin + shlex.quote(json.dumps(body)))
    body["password"] = "hunter 2"
    machine.succeed(signin + shlex.quote(json.dumps(body)))
    config = json.loads(machine.succeed("curl --fail -b cookies http://localhost:9090/dash/api/config"))["data"]
    assert config["server"]["version"] == "${pkgs.stremthru.version}", config["server"]
    assert config["server"]["data_dir"] == "/var/lib/stremthru", config["server"]
    assert config["instance"]["base_url"] == "https://stremthru.example.com", config["instance"]
    assert not config["instance"]["is_public_instance"], config["instance"]
    assert config["instance"]["stremio_locked"], config["instance"]
    assert config["network"]["machine_ip"] == "192.0.2.1", config["network"]
    assert "peer_url" not in config["network"], config["network"]
    features = {f["name"]: f["enabled"] for f in config["features"]}
    assert not features["dmm_hashlist"] and not features["imdb_title"], features

    for node in [minimal, machine]:
        node.succeed("test -f /var/lib/stremthru/stremthru.db")
        node.fail("journalctl -u stremthru.service | grep -E 'read-only file system|permission denied'")
  '';
}
