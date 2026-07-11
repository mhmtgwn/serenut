#!/bin/bash
# clean_production_tests.sh
# Removes compiled test files from production server directories

echo "🧹 Cleaning up compiled test artifacts on VPS..."
if [ -d "/var/www/serenut-api/dist/test" ]; then
  rm -rf /var/www/serenut-api/dist/test
  echo "✅ Compiled test folder /var/www/serenut-api/dist/test deleted successfully."
else
  echo "ℹ️ No compiled test folder found at /var/www/serenut-api/dist/test."
fi
