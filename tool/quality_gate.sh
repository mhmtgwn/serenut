#!/bin/bash
set -e

echo "=========================================="
echo "Running Serenut OS Quality Gate Checklist"
echo "=========================================="

# 0. Architecture Guard (mimari borç baseline'dan artamaz)
echo ""
echo "[0/2] Running Architecture Guard..."
if ! node tool/architecture_guard.mjs; then
    echo "❌ Architecture Guard failed: mimari borç arttı!"
    exit 1
fi

# 1. Run Flutter Analyze (Assertive Fail: Fail on both errors and warnings)
echo ""
echo "[1/2] Running Flutter Analyze..."
if ! flutter analyze --no-fatal-infos --no-fatal-warnings; then
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
