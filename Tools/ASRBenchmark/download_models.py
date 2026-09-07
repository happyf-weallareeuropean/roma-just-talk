"""Download pinned research artifacts; run on the disposable benchmark Mac."""
from pathlib import Path
from huggingface_hub import snapshot_download
import argparse
import json

MODELS = {
    "qwen": ("Qwen/Qwen3-ASR-0.6B", "5eb144179a02acc5e5ba31e748d22b0cf3e303b0", [
        "*.json", "*.safetensors", "*.txt", "*.tiktoken", "LICENSE*", "README.md"]),
    "breeze": ("MediaTek-Research/Breeze-ASR-25", "cffe7ccb404d025296a00758d0a33468bec3a9d0", [
        "*.json", "*.safetensors", "*.txt", "LICENSE*", "README.md"]),
    "xasr": ("GilgameshWind/X-ASR-zh-en", "689ff18c584d29910da37b6fe904db0c1489c9d1", [
        "deployment/models/chunk-160ms-model/*", "deployment/models/chunk-480ms-model/*"]),
    "sensevoice": ("FluidInference/sensevoice-small-coreml", "cdea3526163035c19915d4a10268992d018ebd46", [
        "SenseVoicePreprocessor.mlmodelc/**", "SenseVoiceSmall_int8.mlmodelc/**", "vocab.json"]),
    "parakeet": ("FluidInference/parakeet-tdt-0.6b-v2-coreml", "ee09c569f73759e6d44c9bd16766f477b2b36d39", [
        "Encoder.mlmodelc/**", "Decoder.mlmodelc/**", "JointDecision.mlmodelc/**",
        "Preprocessor.mlmodelc/**", "parakeet_vocab.json", "config.json"]),
}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("model", choices=MODELS)
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    repo, revision, patterns = MODELS[args.model]
    # FluidAudio's Parakeet loader resolves this canonical sibling directory.
    directory = args.root / (repo.split("/")[-1] if args.model == "parakeet" else args.model)
    snapshot_download(repo, revision=revision, allow_patterns=patterns, local_dir=directory, max_workers=4)
    print(json.dumps({"model": args.model, "repo": repo, "revision": revision,
                      "directory": str(directory), "file_bytes": sum(
                          p.stat().st_size for p in directory.rglob("*")
                          if p.is_file() and ".cache" not in p.parts)}), flush=True)
