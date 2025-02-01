#!/bin/bash

# Define the directories to exclude
EXCLUDE_DIRS=("node_modules" ".git" "dist" "build" "coverage")

# Construct the find command with exclusions
EXCLUDE_ARGS=()
for dir in "${EXCLUDE_DIRS[@]}"; do
  EXCLUDE_ARGS+=(-path "*/$dir/*" -prune -o)
done

# Run the find command to locate large .ts and .tsx files
find . "${EXCLUDE_ARGS[@]}" -type f \( -name "*.ts" -o -name "*.tsx" \) -exec du -h {} + | sort -hr | head -20
