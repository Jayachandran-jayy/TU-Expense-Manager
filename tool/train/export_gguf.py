#!/usr/bin/env python3
"""
export_gguf.py - Converts fine-tuned Hugging Face weights to GGUF and quantizes
to Q4_K_M for on-device inference using llama.cpp.

Usage:
    python3 tool/train/export_gguf.py --model models/qwen2.5-0.5b-expense --output models/qwen2.5-0.5b-expense-q4_k_m.gguf
"""

import argparse
import subprocess
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(
        description="Convert HF model to Q4_K_M GGUF"
    )
    parser.add_argument(
        "--model",
        default="models/qwen2.5-0.5b-expense",
        help="Path to merged Hugging Face model directory",
    )
    parser.add_argument(
        "--output",
        default="models/qwen2.5-0.5b-expense-q4_k_m.gguf",
        help="Output quantized GGUF path",
    )
    parser.add_argument(
        "--llama-cpp-dir",
        default="llama.cpp",
        help="Path to cloned llama.cpp repository",
    )
    args = parser.parse_args()

    model_dir = Path(args.model)
    if not model_dir.exists():
        print(f"Error: Model directory {model_dir} not found.")
        print(
            "Please run tool/train/fine_tune_qwen.py first to generate merged model weights."
        )
        return

    llama_dir = Path(args.llama_cpp_dir)
    convert_script = llama_dir / "convert_hf_to_gguf.py"

    if not convert_script.exists():
        print(f"Error: llama.cpp conversion script not found at {convert_script}.")
        print("Please clone and build llama.cpp first:")
        print("    git clone https://github.com/ggerganov/llama.cpp")
        print("    cd llama.cpp && cmake -B build && cmake --build build --config Release")
        return

    f16_gguf = model_dir / "model-f16.gguf"
    print(f"Step 1: Converting {model_dir} to F16 GGUF...")
    subprocess.run(
        [sys.executable, str(convert_script), str(model_dir), "--outfile", str(f16_gguf)],
        check=True,
    )

    quantize_bin = llama_dir / "build" / "bin" / "llama-quantize"
    if not quantize_bin.exists():
        quantize_bin = llama_dir / "llama-quantize"

    print(f"Step 2: Quantizing to Q4_K_M at {args.output}...")
    subprocess.run(
        [str(quantize_bin), str(f16_gguf), args.output, "q4_k_m"],
        check=True,
    )

    if f16_gguf.exists():
        f16_gguf.unlink()

    print(f"Export complete! Model ready for on-device use: {args.output}")


if __name__ == "__main__":
    main()
