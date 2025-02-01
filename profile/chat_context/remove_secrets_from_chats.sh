#!/bin/bash

# Define regex patterns for secrets
declare -A patterns=(
    ["Hugging Face Tokens"]="hf_[A-Za-z0-9]{20,}"
    ["Anthropic API Keys"]="sk-ant-[A-Za-z0-9_-]{40,}"
    ["Prefect API Keys"]="pnu_[A-Za-z0-9]{30,}"
    ["Prefect API URLs"]="https://api\\.prefect\\.cloud/api/accounts/[A-Za-z0-9-]+/workspaces/[A-Za-z0-9-]+"
    ["Azure Client IDs"]="\"client_id\":\\s*\"[a-f0-9-]{36}\""
    ["Azure Client Secrets"]="\"client_secret\":\\s*\"[A-Za-z0-9~_.+-]+\""
    ["Azure Subscription IDs"]="\"subscription_id\":\\s*\"[a-f0-9-]{36}\""
    ["Azure Tenant IDs"]="\"tenant_id\":\\s*\"[a-f0-9-]{36}\""
    ["API Keys"]="[A-Za-z0-9]{20,}_?[A-Za-z0-9]{20,}"
    ["OAuth Tokens"]="[A-Za-z0-9_-]*[A-Za-z0-9]{20,}[A-Za-z0-9_-]*"
    ["Passwords"]="\"password\":\\s*\"[^\"]+\""
    ["Access Keys"]="\"(aws|azure|gcp|api|access|private|secret|auth|client)[_-]?(key|token|id|secret)\":\\s*\"[^\"]+\""
)

# Initialize counters
declare -A total_counts
total_files=0

# Create a log file to track removed secrets
log_file="removed_secrets.log"
echo "🔍 Secret Removal Log - $(date)" > "$log_file"
echo "-----------------------------------" >> "$log_file"

# Find all JSON and JSONL files recursively
find . -type f \( -name "*.json" -o -name "*.jsonl" \) | while read -r file; do
    echo "🔍 Processing: $file"
    file_violation_count=0

    # Read file content
    content=$(cat "$file")

    # Check for each type of secret
    for category in "${!patterns[@]}"; do
        pattern="${patterns[$category]}"
        count=$(grep -Eoc "$pattern" "$file" 2>/dev/null)
        count=${count:-0}  # Ensure count is a number

        if [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]; then
            echo "   ⚠️  Found $count $category"
            total_counts[$category]=$((total_counts[$category] + count))
            file_violation_count=$((file_violation_count + count))

            # Log removed secrets
            grep -Eo "$pattern" "$file" >> "$log_file"

            # Replace secrets with [REDACTED]
            content=$(echo "$content" | sed -E "s/${pattern}/\"[REDACTED]\"/g")
        fi
    done

    # Only overwrite the file if secrets were found
    if [[ "$file_violation_count" -gt 0 ]]; then
        echo "$content" > "$file"
        echo "   ✅ Cleaned $file ($file_violation_count violations removed)"
        total_files=$((total_files + 1))
    fi
done

# Print final summary
echo ""
echo "🎉 Secret Removal Complete!"
echo "----------------------------"
echo "📂 Total files modified: $total_files"
for category in "${!total_counts[@]}"; do
    echo "🔹 ${category}: ${total_counts[$category]}"
done
echo "----------------------------"
echo "🔍 Log saved to $log_file"
