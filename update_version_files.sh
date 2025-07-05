#!/bin/bash

new_version="$1"

# Detect OS and use appropriate sed syntax
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/^version: .*/version: ${new_version}/" step.yml
else
    # Linux/GitHub Actions
    sed -i "s/^version: .*/version: ${new_version}/" step.yml
fi

echo "Updated version to ${new_version} in step.yml"
