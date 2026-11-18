{
  lib,
  config,
  ...
}:
# Target hardware: NVIDIA RTX PRO 6000 Blackwell, 96 GB GDDR7, one of two.
let
  imgSize = 1024;
  model = "Qwen/Qwen3.8-27B-FP8";
  # Placeholders until the card is installed, from `nvidia-smi -L` and the
  # minor number of its device node.
  gpu = {
    uuid = "GPU-00000000-0000-0000-0000-000000000000";
    device = "/dev/nvidia1";
  };
  # Shared by the generating worker and its detector.
  watermark.settings = {
    algorithm = "gumbel";
    # Gumbel is deterministic per context, so unmarked prompt contexts let retries vary.
    deduplicate_contexts = "all";
  };
in
lib.mkIf config.custom.enableNvidia {
  assertions = [
    {
      assertion = lib.all (model: model.watermark != null) (
        lib.attrValues config.services.llmhop.vllm.models
      );
      message = "pythia serves only watermarked output, so every vLLM model needs a `watermark`.";
    }
  ];

  services.llmhop.vllm = {
    enable = true;

    # https://docs.vllm.ai/en/stable/cli/serve/
    modelSettings = {
      attention-backend = "flashinfer";
      enable-auto-tool-choice = true;
      enable-prefix-caching = true;
      gpu-memory-utilization = 0.95;
      kv-cache-dtype = "fp8";
      kv-offloading-size = 16; # GiB
      max-model-len = "256K"; # native maximum
      max-num-batched-tokens = 16384;
      max-num-seqs = 8;
      limit-mm-per-prompt = {
        image = {
          # image.count * image.size * max-num-seqs <= max-num-batched-tokens
          count = 2;
          width = imgSize;
          height = imgSize;
        };
        video = {
          count = 0;
        };
        audio = {
          count = 0;
        };
      };
    };

    # https://docs.vllm.ai/en/latest/configuration/conserving_memory/
    models."qwen3.8-27b" = {
      inherit model watermark;
      # Confined to its card, leaving the other one and the A400 alone.
      environment.CUDA_VISIBLE_DEVICES = gpu.uuid;
      native.devices = [
        "/dev/nvidiactl"
        "char-nvidia-uvm"
        gpu.device
      ];
      # https://unsloth.ai/docs/models/qwen3.8
      # https://recipes.vllm.ai/Qwen/Qwen3.8-27B
      # https://docs.vllm.ai/projects/recipes/en/latest/Qwen/Qwen3.5.html
      settings = {
        reasoning-parser = "qwen3";
        tool-call-parser = "qwen3_xml";
        override-generation-config = {
          min_p = 0.0;
          presence_penalty = 0.0;
          repetition_penalty = 1.0;
          temperature = 1.0;
          top_k = 20;
          top_p = 0.95;
        };
        mm-processor-kwargs = {
          images_kwargs.size = {
            longest_edge = imgSize * imgSize;
            shortest_edge = 4096;
          };
        };
      };
    };

    detectors.watermark.profiles."qwen3.8-27b" = {
      tokenizer = model;
      inherit watermark;
    };
  };
}
