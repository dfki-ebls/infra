# Target hardware: three NVIDIA RTX PRO 6000 Blackwell, 96 GB GDDR7 each.
# Qwen3.8 owns the two Workstation Editions, while the embedding and OCR models
# share the Max-Q through their own `gpu-memory-utilization`.
{ lib, config, ... }:
let
  imgSize = 2048;
  # Frames sampled from a video, and their size.
  videoFrames = 64;
  videoSize = 640;
  # The official repository's tokenizer, which every quantization shares, keeps
  # detection independent of the checkpoint served.
  tokenizer = "Qwen/Qwen3.8-27B";
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
  # Leaves host memory to the pinned KV offloading of Qwen3.8 below (32 GiB).
  boot.extraModprobeConfig = "options zfs zfs_arc_max=${toString (32 * 1024 * 1024 * 1024)}";

  services.llmhop.vllm = {
    enable = true;

    # https://docs.vllm.ai/en/stable/cli/serve/
    models = {
      # One engine over both cards, whose single prefix cache serves every
      # turn of a session.
      "qwen3.8-27b" = {
        model = "nvidia/Qwen3.8-27B-NVFP4";
        # Both Workstation Editions at PCI 11:00.0 and F1:00.0, see README.
        environment.CUDA_VISIBLE_DEVICES = "0,2";
        inherit watermark;
        # https://unsloth.ai/docs/models/qwen3.8
        # https://recipes.vllm.ai/Qwen/Qwen3.8-27B
        settings = {
          tensor-parallel-size = 2;
          attention-backend = "flashinfer";
          # A card holds more FP8 KV cache than its compute can serve, so
          # NVFP4 would only cost accuracy.
          kv-cache-dtype = "fp8";
          # GiB of pinned host memory over both cards, larger than their GPU
          # KV cache so that offloaded prefixes add hits.
          kv-offloading-size = 160;
          max-num-seqs = 256;
          max-num-batched-tokens = 16384;
          # Caps the chunk of a long prompt at a fair share of the batch, so
          # short requests are not stuck behind an agent's long context.
          long-prefill-token-threshold = 4096;
          long-prefill-token-threshold-adaptive = true;
          # Admits queued requests whose prefix is cached first, before
          # others evict it.
          cache-aware-admission-window = 16;
          reasoning-parser = "qwen3";
          enable-auto-tool-choice = true;
          tool-call-parser = "qwen3_xml";
          # The watermark requires probabilistic drafting. Three tokens, the
          # recipe's default, suit the few concurrent sessions this engine
          # serves, whose decoding is bound by weight loading.
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
          # A token covers 32x32 pixels, or two frames of them, so each image
          # and video fits `max-num-batched-tokens`. Media arrive as data URLs,
          # since the server has no network.
          limit-mm-per-prompt = {
            image = {
              count = 16;
              width = imgSize;
              height = imgSize;
            };
            video = {
              count = 1;
              num_frames = videoFrames;
              width = videoSize;
              height = videoSize;
            };
            audio.count = 0;
          };
          media-io-kwargs.video.num_frames = videoFrames;
          mm-processor-kwargs = {
            images_kwargs.size = {
              longest_edge = imgSize * imgSize;
              shortest_edge = 4096;
            };
            # The pixels of two frames, which the encoder merges into one.
            videos_kwargs.size = {
              longest_edge = 2 * videoSize * videoSize;
              shortest_edge = 4096;
            };
          };
          # Each card encodes its share of the images with the whole vision
          # tower, rather than all of them with half of it.
          mm-encoder-tp-mode = "data";
          # GiB of preprocessed media, which a conversation resends every
          # turn, mirrored in the API server and the engine.
          mm-processor-cache-gb = 8;
        };
      };

      # https://github.com/QwenLM/Qwen3-Embedding
      "qwen3-embedding-4b" = {
        model = "Qwen/Qwen3-Embedding-4B";
        # The Max-Q at PCI 21:00.0.
        environment.CUDA_VISIBLE_DEVICES = "1";
        settings = {
          runner = "pooling";
          convert = "embed";
          quantization = "fp8_per_block";
          gpu-memory-utilization = 0.2;
          max-model-len = "32K"; # trained length
          # Trained with MRL, so requests may truncate with `dimensions`.
          hf-overrides.is_matryoshka = true;
        };
      };

      # Server-side defaults let any client send a bare chat completion of
      # one page image, optionally with the text `grounding` for layout
      # boxes. Docling's `lightonocr3_4b` preset needs its `model` param set
      # to this name, which LightOn's client reads from the server.
      # https://github.com/lightonai/LightOnOCR
      "lightonocr-3-4b" = {
        model = "lightonai/LightOnOCR-3-4B";
        environment.CUDA_VISIBLE_DEVICES = "1";
        settings = {
          quantization = "fp8_per_block";
          # Reads the page in full precision.
          quantization-config.ignore = [ "visual.*" ];
          # KV cache for the pages in flight below.
          gpu-memory-utilization = 0.7;
          max-model-len = 18000;
          # Pages in flight, as LightOn's client keeps.
          max-num-seqs = 64;
          # Every page is new, so caching would only cost memory.
          enable-prefix-caching = false;
          mm-processor-cache-gb = 0;
          limit-mm-per-prompt = {
            image = {
              count = 1;
              width = 2048;
              height = 2048;
            };
            video.count = 0;
          };
          default-chat-template-kwargs.enable_thinking = false;
          # Upstream advises against greedy decoding.
          override-generation-config.temperature = 0.1;
        };
      };
    };

    detectors.watermark.profiles = {
      "qwen3.8-27b" = {
        inherit tokenizer;
        inherit watermark;
      };
      # Text marked before MTP was enabled.
      "qwen3.8-27b-gumbel" = {
        inherit tokenizer;
        watermark.settings = {
          algorithm = "gumbel";
          deduplicate_contexts = "all";
        };
      };
    };
  };
}
