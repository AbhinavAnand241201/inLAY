#!/usr/bin/env bash
# Regenerates registry.json and copies it where the CLI and website read it.
set -euo pipefail
cd "$(dirname "$0")/.."
swift scripts/build-registry.swift
cp registry.json cli/Sources/inlay/Resources/registry.json
cp registry.json website/data/registry.json
echo "✓ Synced registry.json → cli/Sources/inlay/Resources/registry.json"
echo "✓ Synced registry.json → website/data/registry.json (Next.js app reads this)"
