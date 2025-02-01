#!/usr/bin/env python3
"""
Token counter for JSON/JSONL chat exports.
Parses JSON structure while being tolerant of chat export quirks.
"""

import tiktoken
import json
import argparse
from typing import Dict, List, Optional, Any, Tuple
import statistics


def count_tokens(text: str, encoder: tiktoken.Encoding) -> int:
    """Count tokens in a text string."""
    try:
        return len(encoder.encode(text))
    except Exception:
        return 0


def analyze_chat_entry(entry: Dict[str, Any], encoder: tiktoken.Encoding) -> int:
    """
    Analyze a single chat entry, focusing on common chat message structures.
    Returns total tokens in the entry.
    """
    total_tokens = 0

    # Common chat message fields to look for
    text_fields = ['content', 'text', 'message', 'prompt', 'completion', 'response']

    def process_value(value: Any) -> int:
        tokens = 0
        if isinstance(value, str):
            tokens += count_tokens(value, encoder)
        elif isinstance(value, dict):
            tokens += process_dict(value)
        elif isinstance(value, list):
            for item in value:
                tokens += process_value(item)
        return tokens

    def process_dict(d: Dict[str, Any]) -> int:
        tokens = 0
        # Prioritize known message fields
        for field in text_fields:
            if field in d and isinstance(d[field], str):
                tokens += count_tokens(d[field], encoder)

        # Process all other fields
        for key, value in d.items():
            if key not in text_fields:  # Skip already processed fields
                tokens += process_value(value)
        return tokens

    return process_value(entry)


def analyze_file(file_path: str, encoder: tiktoken.Encoding) -> Tuple[List[int], Dict[str, int]]:
    """
    Analyze a JSON or JSONL file for token usage.
    Returns list of token counts per entry and overall statistics.
    """
    entry_tokens = []

    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
        try:
            # Try parsing as single JSON first
            data = json.loads(content)
            if isinstance(data, list):
                # Handle array of entries
                for entry in data:
                    tokens = analyze_chat_entry(entry, encoder)
                    if tokens > 0:
                        entry_tokens.append(tokens)
            elif isinstance(data, dict):
                # Handle single entry or nested structure
                if any(key in data for key in ['messages', 'conversations', 'data', 'entries']):
                    # Look for array fields containing chat messages
                    for key in ['messages', 'conversations', 'data', 'entries']:
                        if key in data and isinstance(data[key], list):
                            for entry in data[key]:
                                tokens = analyze_chat_entry(entry, encoder)
                                if tokens > 0:
                                    entry_tokens.append(tokens)
                else:
                    # Treat as single entry
                    tokens = analyze_chat_entry(data, encoder)
                    if tokens > 0:
                        entry_tokens.append(tokens)
        except json.JSONDecodeError:
            # Try parsing as JSONL
            f.seek(0)
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                    tokens = analyze_chat_entry(entry, encoder)
                    if tokens > 0:
                        entry_tokens.append(tokens)
                except json.JSONDecodeError:
                    continue

    if not entry_tokens:
        print("Warning: No valid entries found in file")
        return [], {}

    stats = {
        "total_tokens": sum(entry_tokens),
        "total_entries": len(entry_tokens),
        "avg_tokens_per_entry": int(statistics.mean(entry_tokens)),
        "median_tokens_per_entry": int(statistics.median(entry_tokens)),
        "max_tokens": max(entry_tokens),
        "min_tokens": min(entry_tokens)
    }

    return entry_tokens, stats


def main() -> None:
    parser = argparse.ArgumentParser(
        description='Count tokens in JSON/JSONL chat exports'
    )
    parser.add_argument('file', help='JSON or JSONL file to analyze')
    parser.add_argument(
        '--model',
        default='cl100k_base',
        help='Tiktoken model name (default: cl100k_base)'
    )
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Show token distribution details'
    )

    args = parser.parse_args()
    encoder = tiktoken.get_encoding(args.model)

    entry_tokens, stats = analyze_file(args.file, encoder)

    if stats:
        print(f"\nToken Analysis Summary:")
        print(f"Total Tokens: {stats['total_tokens']:,}")
        print(f"Total Entries: {stats['total_entries']:,}")
        print(f"Average Tokens per Entry: {stats['avg_tokens_per_entry']:,}")
        print(f"Median Tokens per Entry: {stats['median_tokens_per_entry']:,}")
        print(f"Max Tokens in Single Entry: {stats['max_tokens']:,}")
        print(f"Min Tokens in Single Entry: {stats['min_tokens']:,}")

        if args.verbose:
            # Print token distribution in 10k token buckets
            buckets = {}
            for tokens in entry_tokens:
                bucket = (tokens // 10000) * 10000
                buckets[bucket] = buckets.get(bucket, 0) + 1

            print("\nToken Distribution (in 10k token buckets):")
            for bucket in sorted(buckets.keys()):
                print(f"{bucket:,}-{bucket + 9999:,}: {buckets[bucket]:,} entries")


if __name__ == "__main__":
    main()