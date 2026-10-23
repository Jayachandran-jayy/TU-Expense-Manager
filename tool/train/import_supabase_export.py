#!/usr/bin/env python3
"""
import_supabase_export.py - Converts a CSV exported from the Supabase
`sms_contributions` table (see server/contrib/schema.sql) into the
contributions.jsonl format that curate_exemplars.py reads.

Rows already present in the output file (matched by id) are skipped, so
monthly exports can be imported again without duplicates.

Usage:
    python3 tool/train/import_supabase_export.py export.csv [contributions.jsonl]
"""

import csv
import json
import sys
from pathlib import Path


def load_seen_ids(out_path: Path) -> set:
    seen = set()
    if not out_path.exists():
        return seen
    with open(out_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                seen.add(json.loads(line).get("id"))
            except json.JSONDecodeError:
                continue
    return seen


def to_item(row: dict) -> dict:
    amount = (row.get("amount") or "").strip()
    return {
        "id": row.get("id"),
        "bank": (row.get("bank") or "").strip(),
        "type": (row.get("txn_type") or "debit").strip().lower(),
        "amount": float(amount) if amount else None,
        "merchant": (row.get("merchant") or "").strip(),
        "sanitized_sms": (row.get("sanitized_sms") or "").strip(),
    }


def main(argv: list) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 1

    csv_path = Path(argv[1])
    out_path = Path(argv[2]) if len(argv) > 2 else Path("contributions.jsonl")

    if not csv_path.exists():
        print(f"Error: {csv_path} not found.")
        return 1

    seen = load_seen_ids(out_path)
    added = 0
    with open(csv_path, "r", encoding="utf-8", newline="") as src, \
            open(out_path, "a", encoding="utf-8") as dst:
        for row in csv.DictReader(src):
            item = to_item(row)
            if not item["sanitized_sms"] or item["id"] in seen:
                continue
            dst.write(json.dumps(item, ensure_ascii=False) + "\n")
            seen.add(item["id"])
            added += 1

    print(f"Added {added} new sample(s) to {out_path}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
