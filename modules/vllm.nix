# vLLM behind llmhop on every host enabling it, which declares its own models
# and detectors.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.llmhop.vllm;
  # Every watermark of a model or detector profile, each naming its key.
  watermarks =
    lib.filter (watermark: watermark != null) (lib.catAttrs "watermark" (lib.attrValues cfg.models))
    ++ lib.concatMap (detector: lib.catAttrs "watermark" (lib.attrValues detector.profiles)) (
      lib.attrValues cfg.detectors
    );
in
lib.mkIf cfg.enable {
  # An unsigned 64-bit integer, as vLLM requires.
  custom.credstore = lib.genAttrs (lib.catAttrs "credential" watermarks) (
    _: "od -An -N8 -tu8 /dev/urandom | tr -d ' '"
  );

  services.llmhop.vllm = {
    package = pkgs.vllm;
    uid = 503;

    environment.CUDA_HOME = "${pkgs.vllm.cudaHome}";

    # Optional, skipped while missing.
    fetch.hfTokenCredential = "huggingface.token";
  };

  # Members of `wheel` read the metrics with `llmhop top`, without root.
  services.llmhop.gateway.listen.wheel = {
    socketGroup = "wheel";
    metrics = true;
  };
}
