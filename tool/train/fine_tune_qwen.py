#!/usr/bin/env python3
"""
fine_tune_qwen.py - Fine-tunes Qwen2.5-0.5B-Instruct on financial bank SMS
extraction using LoRA and Hugging Face SFTTrainer.

Usage:
    python3 tool/train/fine_tune_qwen.py --data data/contributions.jsonl --output models/qwen2.5-0.5b-expense
"""

import argparse
import json
from pathlib import Path

SYSTEM_PROMPT = (
    "You are an expert bank transaction parser. Extract transaction details from the "
    "bank notification (SMS or email) into JSON format.\n"
    "Output ONLY a single valid JSON object with the following keys:\n"
    '"is_transaction": true or false,\n'
    '"type": "debit" if money was sent, spent, debited, paid, withdrawn, or transferred out; "credit" if money was received, credited, deposited, or refunded,\n'
    '"amount": numeric amount (e.g. 90.0) or null,\n'
    '"currency": "INR",\n'
    '"merchant": recipient, payee, or vendor name or null,\n'
    '"account": card number or account number (e.g. "4668") or null,\n'
    '"reference": RRN, UTR, or UPI reference number or null,\n'
    '"date": transaction date (YYYY-MM-DD) or null\n'
    "Do not include any explanation or thoughts. Output pure JSON only."
)


def format_instruction(item: dict) -> list[dict]:
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
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": f'SMS: "{item.get("sanitized_sms", "")}"'},
        {"role": "assistant", "content": json.dumps(expected)},
    ]


def main():
    parser = argparse.ArgumentParser(
        description="Fine-tune Qwen2.5-0.5B for SMS parsing"
    )
    parser.add_argument(
        "--data", default="data/contributions.jsonl", help="Path to JSONL dataset"
    )
    parser.add_argument(
        "--output",
        default="models/qwen2.5-0.5b-expense",
        help="Output directory for merged weights",
    )
    parser.add_argument(
        "--epochs", type=int, default=3, help="Number of training epochs"
    )
    parser.add_argument(
        "--base-model",
        default="Qwen/Qwen2.5-0.5B-Instruct",
        help="Base Hugging Face model",
    )
    args = parser.parse_args()

    data_file = Path(args.data)
    if not data_file.exists():
        print(f"Error: Dataset {data_file} does not exist.")
        print(
            "Please compile accepted GitHub issues into a .jsonl file first."
        )
        return

    print(
        f"Starting fine-tuning pipeline for {args.base_model} on {data_file}..."
    )

    try:
        import torch
        from datasets import Dataset
        from peft import LoraConfig, get_peft_model
        from transformers import AutoModelForCausalLM, AutoTokenizer, TrainingArguments
        from trl import SFTTrainer
    except ImportError:
        print(
            "Required packages not found. Please run: pip install -r tool/train/requirements.txt trl"
        )
        return

    # Load data
    samples = []
    with open(data_file, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                samples.append(json.loads(line))

    formatted = [format_instruction(s) for s in samples]
    dataset = Dataset.from_dict({"messages": formatted})

    tokenizer = AutoTokenizer.from_pretrained(args.base_model)
    model = AutoModelForCausalLM.from_pretrained(
        args.base_model,
        torch_dtype=torch.bfloat16 if torch.cuda.is_available() else torch.float32,
        device_map="auto" if torch.cuda.is_available() else None,
    )

    lora_config = LoraConfig(
        r=16,
        lora_alpha=32,
        target_modules=[
            "q_proj",
            "k_proj",
            "v_proj",
            "o_proj",
            "gate_proj",
            "up_proj",
            "down_proj",
        ],
        lora_dropout=0.05,
        bias="none",
        task_type="CAUSAL_LM",
    )

    training_args = TrainingArguments(
        output_dir=args.output,
        num_train_epochs=args.epochs,
        per_device_train_batch_size=4,
        gradient_accumulation_steps=2,
        learning_rate=2e-4,
        logging_steps=10,
        save_strategy="epoch",
        bf16=torch.cuda.is_available(),
    )

    trainer = SFTTrainer(
        model=model,
        train_dataset=dataset,
        peft_config=lora_config,
        args=training_args,
    )

    trainer.train()
    print("Training finished. Merging LoRA adapters...")
    merged = trainer.model.merge_and_unload()
    merged.save_pretrained(args.output)
    tokenizer.save_pretrained(args.output)
    print(f"Model successfully saved to {args.output}!")


if __name__ == "__main__":
    main()
