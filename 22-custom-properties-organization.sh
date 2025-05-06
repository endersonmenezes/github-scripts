#!/usr/bin/env bash

###############################################################################
# GitHub Organization Custom Properties Update Tool
#
# Author: Enderson Menezes
# Created: 2025-05-06
#
# Description:
#   This script updates custom properties for GitHub organization based on a CSV
#   input file.
#
# Input File Format (22-custom-properties-organization.csv):
#   owner,name,value_type,required,default_value,description,allowed_values
#
# Usage: bash 22-custom-properties-organization.sh
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

# Process the CSV file
create_custom_property() {
    local owner=$1
    local name=$2
    local value_type=$3
    local required=$4
    local default_value=$5
    local description=$6
    local allowed_values=$7
    echo "Creating custom property '$name' for organization $owner..."
    #TODO: Implement the API call to create the custom property
}

while IFS=',' read -r owner name value_type required default_value description allowed_values; do
  # Skip the header line
  if [[ "$owner" == "owner" ]]; then
    continue
  fi

  # Check if the property already exists

  check_property_exists "$owner" "$name"
  if [ $? -eq 0 ]; then
    echo "Property '$name' already exists for organization $owner. Skipping..."
    continue
  fi

  # Create the custom property
  create_custom_property "$owner" "$name" "$value_type" "$required" "$default_value" "$description" "$allowed_values"
done < "$FILE"