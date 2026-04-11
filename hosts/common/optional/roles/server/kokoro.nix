{ config, lib, ... }: {

  options = {
    kokoro.enable =
      lib.mkEnableOption "enables Kokoro TTS server";
  };

  config = lib.mkIf config.kokoro.enable {

    virtualisation.oci-containers.containers.kokoro = {
      image = "ghcr.io/remsky/kokoro-fastapi-gpu:latest";
      ports = [ "8880:8880" ];
      environment = {
        USE_GPU = "true";
        PYTHONUNBUFFERED = "1";
      };
      extraOptions = [ "--device" "nvidia.com/gpu=all" ];
    };

    networking.firewall.allowedTCPPorts = [ 8880 ];
  };
}
