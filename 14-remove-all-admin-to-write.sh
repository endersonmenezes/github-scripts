#!/usr/bin/env bash

###############################################################################
# GitHub Team Permission Downgrade Tool
#
# Author: Enderson Menezes
# Created: 2024-08-12
# Updated: 2025-03-14
#
# Description:
#   This script downgrades all team permissions on repositories from admin
#   to write (push) level. It's useful for security compliance and
#   implementing least-privilege access controls across repositories.
#
# Usage: bash 14-remove-all-admin-to-write.sh <org> <team>
#
# Parameters:
#   - org: GitHub organization name
#   - team: Team slug within the organization
###############################################################################

# Read Common Functions
source functions.sh

# Verify GH is installed
is_gh_installed

# Create a SHA256 of the file for audit (Define SHA256 varible)
audit_file

# Args
PARALLEL_JOBS=2
ORGANIZATION=$1
TEAM=$2
REPO_FILES="repos.json"

# Function to downgrade team permission
function update_permission(){
    OWNER=$1
    TEAM=$2
    REPO=$3
    PERMISSION=$4
    API_URL="/orgs/$OWNER/teams/$TEAM/repos/$OWNER/$REPO"
    echo "Downgrading ${TEAM} to ${TARGET_ROLE} on ${OWNER}/${REPO} on ${API_URL}" 
    gh api \
        --method PUT \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        $API_URL \
        -f "permission=${PERMISSION}" > /dev/null
}

# List team repositories
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  --paginate \
  /orgs/$ORGANIZATION/teams/$TEAM/repos > $REPO_FILES

# For item in REPO_FILES
for row in $(jq -r '.[] | @base64' $REPO_FILES); do
    _jq() {
        echo ${row} | base64 --decode | jq -r ${1}
    }
    OWNER=$(_jq '.owner.login')
    REPO=$(_jq '.name')
    ACTUAL_ROLE=$(_jq '.role_name')
    TARGET_ROLE="push"
    # if role name is admin, downgrade to write
    if [[ "${ACTUAL_ROLE}" == "admin" ]]; then
        update_permission $OWNER $TEAM $REPO "$TARGET_ROLE"
    fi
done