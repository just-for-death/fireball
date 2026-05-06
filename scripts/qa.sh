#!/usr/bin/env bash
set -euo pipefail

echo "==> Running flutter analyze"
flutter analyze

echo
echo "==> Running flutter test"
flutter test

echo
echo "QA automated checks passed."
