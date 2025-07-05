#!/bin/bash

new_version="$1"
file_path="step.yml"

sed -i '' "s/^version: .*/version: ${new_version}/" "${file_path}"

echo "Updated version to ${new_version} in ${file_path}"