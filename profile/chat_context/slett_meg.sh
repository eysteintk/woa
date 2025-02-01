#!/bin/bash

# Define the file and line number
file="conversations.json"
line_number=238655

# Check if the file exists
if [[ ! -f "$file" ]]; then
    echo "❌ Error: File '$file' not found!"
    exit 1
fi

# Print the specific line with context
echo "🔍 Extracting secret from: $file (Line: $line_number)"
sed -n "$((line_number-2)),$((line_number+2))p" "$file"

