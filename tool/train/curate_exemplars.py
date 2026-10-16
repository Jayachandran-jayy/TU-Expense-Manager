#!/usr/bin/env python3
"""
curate_exemplars.py - Parses contributed SMS samples and formats them into
curated Dart code for `lib/src/core/rag_exemplars.dart`.

Usage:
    python3 tool/train/curate_exemplars.py [path_to_contributions.jsonl]
"""

import json
import sys
from pathlib import Path


def load_contributions(file_path: Path):
    if not file_path.exists():
        print(f"Error: {file_path} not found.")
        sys.exit(1)

    items = []
    with open(file_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                items.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return items


def generate_dart_exemplar(item: dict) -> str:
    bank = item.get("bank", "General").strip()
    bank_id = (
        bank.lower()
        .replace(" ", "_")
        .replace("-", "_")
        + "_"
        + item.get("type", "debit").lower()
    )
    raw_sms = item.get("sanitized_sms", "").replace("'", "\\'").replace('"', '\\"')
    expected = {
        "is_transaction": True,
        "type": item.get("type", "debit").lower(),
        "amount": item.get("amount"),
        "currency": "INR",
        "merchant": item.get("merchant", "Unknown"),
        "account": item.get("account"),
        "reference": item.get("reference", "[MASKED]"),
        "date": item.get("date"),
    }

    keywords = [
        k.lower()
        for k in bank.split() + [item.get("type", "debit"), "rs", "inr"]
        if len(k) >= 2
    ]

    return f"""    RagExemplar(
      id: '{bank_id}',
      bank: '{bank}',
      keywords: <String>{json.dumps(keywords)},
      rawSms: '{raw_sms}',
      expectedJson: <String, dynamic>{json.dumps(expected)},
    ),"""


def main():
    path = (
        Path(sys.argv[1])
        if len(sys.argv) > 1
        else Path("data/raw_contributions.jsonl")
    )
    if not path.exists():
        print(f"Dataset file '{path}' not found. Please provide a valid JSONL file.")
        print("Example JSONL line:")
        print(
            '{"bank": "HDFC Bank", "type": "debit", "amount": 450.0, "merchant": "Swiggy", "sanitized_sms": "Rs 450 spent on HDFC Card ending *XXXX at Swiggy."}'
        )
        return

    items = load_contributions(path)
    print(f"Loaded {len(items)} contributions from {path}.\n")
    print("Generated Dart Exemplars:\n")
    for item in items:
        print(generate_dart_exemplar(item))


if __name__ == "__main__":
    main()
