#!/usr/bin/env bash

###############################################################################
# GitHub Repository Custom Properties Update Tool
#
# Author: Enderson Menezes
# Created: 2025-04-24
#
# Description:
#   This script updates custom properties for GitHub repositories based on a CSV
#   input file. It first checks if the property exists, then updates its value,
#   and finally verifies the change was applied correctly. All actions are logged
#   for audit purposes.
#
# Input File Format (21-update-repo-properties.csv):
#   owner/repo,property_key,property_value
#   test/repo1,custom_property_1,"value1"
#
# Usage: bash 21-update-repo-properties.sh
###############################################################################

# Read Common Functions
source functions.sh

# Verify GH is installed
is_gh_installed

# Create a SHA256 of the file for audit (Define SHA256 variable)
audit_file

# Read CSV config file (Define FILE variable)
read_config_file

# Configurations
API_VERSION="2022-11-28"
ACCEPT_HEADER="application/vnd.github+json"

# Function to update a custom property
function update_custom_property() {
  local owner=$1
  local repo=$2
  local key=$3
  local value=$4
  
  echo "Updating property '$key' to '$value' for repository $owner/$repo..."
  
  # Create JSON payload for the update
  PAYLOAD="{\"properties\":[{\"property_name\":\"$key\",\"value\": $value}]}"
  
  # Make API call to update the property
  RESPONSE=$(echo $PAYLOAD | gh api \
      --method PATCH \
      -H "Accept: $ACCEPT_HEADER" \
      -H "X-GitHub-Api-Version: $API_VERSION" \
      "/repos/$owner/$repo/properties/values" --input -)
  
  # Check if the update was successful
  HTTP_CODE=$?
  if [ $HTTP_CODE -eq 0 ]; then
    echo "✅ Successfully updated property '$key' for $owner/$repo"
    return 0
  else
    echo "❌ Failed to update property '$key' for $owner/$repo"
    echo "Error response: $RESPONSE"
    return 1
  fi
}

# Function to verify a custom property
function verify_custom_property() {
  local owner=$1
  local repo=$2
  local key=$3
  local expected_value=$4
  
  echo "Verifying property '$key' for repository $owner/$repo..."
  
  # Get current repository properties
  PROPERTIES=$(gh api \
      -H "Accept: $ACCEPT_HEADER" \
      -H "X-GitHub-Api-Version: $API_VERSION" \
      "/repos/$owner/$repo/properties/values")
  
  # Extract the value of the specified property using jq
  # Find the property with the matching name and extract its value
  ACTUAL_VALUE=$(echo $PROPERTIES | jq -r ".[] | select(.property_name==\"$key\") | .value")

  # TRIM AND REMOVE SPACES
  # Handle array values by removing all whitespace between brackets and elements
  if [[ "$ACTUAL_VALUE" == \[*\] && "$expected_value" == \[*\] ]]; then
    # For array values, normalize JSON arrays by removing all whitespace between elements
    # This handles multi-line JSON arrays as well as single-line arrays with spaces
    ACTUAL_VALUE=$(echo "$ACTUAL_VALUE" | tr -d '\n\r' | sed 's/\[\s*/\[/g; s/\s*\]/\]/g; s/\s*,\s*/,/g; s/\s*"\s*/"/g')
    expected_value=$(echo "$expected_value" | tr -d '\n\r' | sed 's/\[\s*/\[/g; s/\s*\]/\]/g; s/\s*,\s*/,/g; s/\s*"\s*/"/g')
  else
    # For non-array values, just trim spaces
    ACTUAL_VALUE=$(echo "$ACTUAL_VALUE" | xargs)
    expected_value=$(echo "$expected_value" | xargs)
  fi
  
  # Check if the property has the expected value
  if [ "$ACTUAL_VALUE" = "$expected_value" ]; then
    echo "✅ Verification successful: Property '$key' has value '$expected_value'"
    return 0
  else
    echo "⚠️ Verification failed: Property '$key' has value '$ACTUAL_VALUE', expected '$expected_value'"
    return 1
  fi
}

function show_separator() {
  echo "----------------------------------------"
}

###############################################################################
# MAIN PROGRAM
###############################################################################

# Process each repository
# Initialize a counter to track line number
LINE_NUMBER=0
while IFS=, read -r repo_path property_key property_value || [ -n "$repo_path" ]; do
  # Increment line counter
  ((LINE_NUMBER++))
  
  # Skip header (first line), comment lines, and empty lines
  [[ "$LINE_NUMBER" -eq 1 || "$repo_path" =~ ^#.*$ || -z "$repo_path" ]] && continue

  # Extract owner and repository name
  OWNER=$(echo $repo_path | awk -F/ '{print $1}')
  REPO=$(echo $repo_path | awk -F/ '{print $2}')
  
  echo "Processing repository: $OWNER/$REPO"
  echo "Property key: $property_key"
  echo "Property value: $property_value"
  
  # Check if both property key and value are provided
  if [ -z "$property_key" ] || [ -z "$property_value" ]; then
    echo "❌ Error: Property key or value is missing for $OWNER/$REPO"
    show_separator
    continue
  fi

  # Update the custom property
  update_custom_property "$OWNER" "$REPO" "$property_key" "$property_value"
  
  # Verify the update
  verify_custom_property "$OWNER" "$REPO" "$property_key" "$property_value"
  
  # Show separator
  show_separator
done < $FILE

echo "Process completed!"
