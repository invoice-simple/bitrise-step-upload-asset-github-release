#!/bin/bash

new_version="$1"

sed -i '' "s/^version: .*/version: ${new_version}/" step.yml

echo "Updated version to ${new_version} in step.yml"