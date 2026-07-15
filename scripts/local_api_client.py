#!/usr/bin/env python3
"""Authenticated command-line client for the voice assistant control API."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from local_api_auth import post_local_api


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("exit", "dnd", "dnd-disable"))
    args = parser.parse_args()
    path = {"exit": "exit", "dnd": "dnd", "dnd-disable": "dnd/disable"}[args.action]
    try:
        with post_local_api(path) as response:
            sys.stdout.buffer.write(response.read())
            sys.stdout.write("\n")
        return 0
    except Exception as exc:
        print(f"local API request failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
