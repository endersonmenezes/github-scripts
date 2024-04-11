#!/usr/bin/env bash

##
# Author: Enderson Menezes
# Created: 2024-03-08
# Description: Archive repositories.
# Usage: bash archive-repos.sh
##

# Read Common Functions
source functions.sh

# Verify GH is installed
is_gh_installed

# Create a SHA256 of the file for audit (Define SHA256 varible)
audit_file

## Read a CSV file (Define FILE variable)
read_config_file

## Owners and Repos
for i in $(cat $FILE | grep -v '^#' | grep -v '^$' | awk -F, '{print $1}'); do
  OWNER=$(echo $i | awk -F/ '{print $1}')
  REPO=$(echo $i | awk -F/ '{print $2}')
  gh repo archive $OWNER/$REPO -y
done