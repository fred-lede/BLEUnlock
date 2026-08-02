#!/bin/bash
set -e
# Clean build output before each compile
for dir in build/Release build/Debug; do
  if [ -d "$dir" ]; then
    rm -rf "${dir:?}/"*
  fi
done
# Run xcodebuild with all remaining arguments
exec xcodebuild "$@"
