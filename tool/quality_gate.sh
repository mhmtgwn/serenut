#!/bin/bash
set -e

echo "=========================================="
echo "Running Serenut POS Quality Gate Checklist"
echo "=========================================="

# 1. Run Flutter Analyze (Assertive Fail: Fail on both errors and warnings)
echo ""
echo "[1/2] Running Flutter Analyze..."
if ! flutter analyze --fatal-warnings; then
    echo "❌ Flutter Analyze found issues!"
    exit 1
else
    echo "✅ Flutter Analyze completed with 0 errors/warnings!"
fi

# 2. Run Flutter Test
echo ""
echo "[2/2] Running Flutter Tests..."
if ! flutter test; then
    echo "❌ Flutter Tests failed!"
    exit 1
else
    echo "✅ All Flutter tests passed successfully!"
fi

echo ""
echo "=========================================="
echo "🎉 Quality Gate Passed Successfully!"
echo "=========================================="
exit 0
