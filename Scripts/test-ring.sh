#!/bin/bash
# Checks the shared frame ring without involving the app or the extension.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

mkdir -p build
clang -O1 -Wall -std=c17 -IShared Tests/RingTest.c Shared/CamfeedRing.c -o build/ringtest
./build/ringtest
