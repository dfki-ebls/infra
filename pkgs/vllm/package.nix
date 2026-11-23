{
  lib,
  pkgs,
  mkUvEnv,
  mkCudaHome,
  fetchpatch2,
  ffmpeg_8-headless,
  rdma-core,
  onetbb,
}:
let
  # https://github.com/vllm-project/vllm/pull/64550
  watermarkKeyFile = fetchpatch2 {
    url = "https://github.com/vllm-project/vllm/commit/059fb66bdc0e25d086ff517f5a9c5e72825c13dd.patch?full_index=1";
    includes = [ "vllm/config/watermarking.py" ];
    hash = "sha256-f/VdbGCT26moEdWVH+YP1+MXszjwFHaeRZnxqhTVPnU=";
  };
  env = mkUvEnv {
    name = "vllm-env";
    workspaceRoot = ./.;
    buildInputs = [
      ffmpeg_8-headless # torchcodec, which supports FFmpeg 4 to 8
      rdma-core # InfiniBand for cuFile and nvshmem
      onetbb # numba's threading layer
    ];
    optionalLibs = [
      # Variants for the FFmpeg majors not supplied above.
      "*/torchcodec/libtorchcodec_*[!8].so"
      # nvshmem plugins for the launchers and fabrics of multi-node jobs.
      "*/nvidia/nvshmem/lib/nvshmem_*.so.3"
    ];
    overlays = [
      # Backports `key_file` of `WatermarkConfig`, which llmhop passes.
      # Wheels are installed without unpacking, so `patches` cannot apply.
      # Drop with vLLM 0.35.
      (final: prev: {
        vllm = prev.vllm.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            patch --forward -p1 -d "$out/${final.python.sitePackages}" < ${watermarkKeyFile}
          '';
        });
      })
    ];
  };
  # `CUDA_HOME` for the JIT compilers, which otherwise look for `which nvcc` and
  # `/usr/local/cuda`. Not the bundled wheels: those are a runtime toolkit, with
  # no `libcudart.so` namelink and no driver stub to link against. The set vLLM's
  # own image installs for runtime JIT (docker/Dockerfile: nvcc, cudart, nvrtc,
  # cuobjdump, cublas, curand), on the CUDA line the lock resolved.
  cudaHome = mkCudaHome {
    name = "vllm-cuda-home";
    packages = with pkgs.${env.cudaPackagesAttr}; [
      cuda_nvcc
      cuda_cudart
      cuda_crt
      cccl
      cuda_nvrtc
      cuda_cuobjdump
      libcublas
      libcurand
    ];
  };
in
lib.lazyDerivation {
  derivation = env;
  passthru = {
    inherit cudaHome;
    inherit (env) python cudaPackagesAttr;
  };
  meta = {
    description = "Python environment providing the vLLM inference server";
    homepage = "https://github.com/vllm-project/vllm";
    license = lib.licenses.asl20;
    mainProgram = "vllm";
    platforms = [ "x86_64-linux" ];
  };
}
