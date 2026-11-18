# Target hardware: NVIDIA RTX PRO 4500 Blackwell, 32 GB GDDR7, used by vLLM alone.
{ lib, config, ... }:
let
  imgSize = 1536;
  # Mixed precision, the smallest build, which leaves the most KV cache.
  model = "unsloth/Qwen3.8-27B-NVFP4";
  # Shared by the generating worker and its detector.
  watermark.settings = {
    # The algorithm that supports speculative decoding.
    algorithm = "dual_key_gumbel";
    # Gumbel is deterministic per context, so unmarked prompt contexts let retries vary.
    deduplicate_contexts = "all";
    # Overrides requests opting out with `watermarking: false`.
    enforce = true;
  };
in
lib.mkIf config.custom.enableNvidia {
  services.llmhop.vllm = {
    enable = true;

    # https://docs.vllm.ai/en/stable/cli/serve/
    # https://docs.vllm.ai/en/latest/configuration/conserving_memory/
    models."qwen3.8-27b" = {
      inherit model watermark;
      # https://unsloth.ai/docs/models/qwen3.8
      # https://recipes.vllm.ai/Qwen/Qwen3.8-27B
      settings = {
        attention-backend = "flashinfer";
        # The extensible KV cache takes the whole card, so
        # `gpu-memory-utilization` stays unset.
        kv-cache-dtype = "nvfp4";
        kv-offloading-size = 16; # GiB
        max-num-batched-tokens = 4096;
        max-num-seqs = 4;
        reasoning-parser = "qwen3";
        enable-auto-tool-choice = true;
        tool-call-parser = "qwen3_xml";
        # The watermark requires probabilistic drafting. Few concurrent
        # requests leave the bandwidth-bound card spare compute to verify
        # longer drafts.
        speculative-config = {
          method = "mtp";
          num_speculative_tokens = 3;
          draft_sample_method = "probabilistic";
        };
        override-generation-config = {
          min_p = 0.0;
          presence_penalty = 0.0;
          repetition_penalty = 1.0;
          temperature = 1.0;
          top_k = 20;
          top_p = 0.95;
        };
        # A token covers 32x32 pixels, so each image fits `max-num-batched-tokens`.
        limit-mm-per-prompt = {
          image = {
            count = 8;
            width = imgSize;
            height = imgSize;
          };
          video.count = 0;
          audio.count = 0;
        };
        mm-processor-kwargs = {
          images_kwargs.size = {
            longest_edge = imgSize * imgSize;
            shortest_edge = 4096;
          };
        };
      };
    };

    detectors.watermark.profiles = {
      "qwen3.8-27b" = {
        tokenizer = model;
        inherit watermark;
      };
      # Text marked before MTP was enabled.
      "qwen3.8-27b-gumbel" = {
        tokenizer = model;
        watermark.settings = {
          algorithm = "gumbel";
          deduplicate_contexts = "all";
        };
      };
    };
  };
}
