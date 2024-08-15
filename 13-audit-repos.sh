#!/usr/bin/env bash

##
# Author: Enderson Menezes
# Created: 2024-08-12
# Description: This script reads a 13-audit-repos.csv file and audit repositories
# Usage: bash audit-repos.sh
##

# Read Common Functions
source functions.sh

# Verify GH is installed
is_gh_installed

# Create a SHA256 of the file for audit (Define SHA256 varible)
audit_file

## Read a CSV file (owner-repo,team,permission) (Define FILE variable)
read_config_file

# Function to get details from PR
get_pr_details_from_url(){
    PR_URL=$1
    PR_NUMBER=$(cut -d'/' -f8 <<< "${PR_URL}")
    OWNER=$(cut -d'/' -f5 <<< "${PR_URL}")
    REPOSITORY=$(cut -d'/' -f6 <<< "${PR_URL}")
    echo "Getting PR details for PR ${PR_NUMBER} on ${OWNER}/${REPOSITORY}"
    gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${PR_URL}" > "${AUDIT_FOLDER}/${OWNER}_${REPOSITORY}/pr_${PR_NUMBER}.json"

    # Status URL .statuses_url
    STATUS_URL=$(jq -r '.statuses_url' "${AUDIT_FOLDER}/${OWNER}_${REPOSITORY}/pr_${PR_NUMBER}.json")
    echo "Getting PR status for PR ${PR_NUMBER} on ${OWNER}/${REPOSITORY}"
    gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${STATUS_URL}" > "${AUDIT_FOLDER}/${OWNER}_${REPOSITORY}/pr_${PR_NUMBER}_status.json"

    # Get Review from PR
    # /repos/{owner}/{repo}/pulls/{pull_number}/reviews
    echo "Getting PR reviews for PR ${PR_NUMBER} on ${OWNER}/${REPOSITORY}"
    gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/${OWNER}/${REPOSITORY}/pulls/${PR_NUMBER}/reviews" > "${AUDIT_FOLDER}/${OWNER}_${REPOSITORY}/pr_${PR_NUMBER}_reviews.json"
}
export -f get_pr_details_from_url

# Specific Config File
if [[ $(head -n 1 $FILE) != "owner,repo,start_date,end_date,query_prs" ]]; then
    echo "The file $FILE does not have the correct format."
    exit 1
fi

# Verify last line
if [[ $(tail -n 1 $FILE) != "" ]]; then
    echo "The file $FILE does not have the correct format."
    echo "Adding a blank line at the end of the file..."
    echo "" >> $FILE
fi
export FILE

# Audit Folder
AUDIT_FOLDER="audit"
if [ ! -d $AUDIT_FOLDER ]; then
    mkdir $AUDIT_FOLDER
fi
export AUDIT_FOLDER

# Read line by line
while IFS=, read -r OWNER REPOSITORY START_DATE END_DATE QUERY_PRS; do
    
    # Ignore Cases
    if [[ $OWNER == "owner" ]]; then
        continue
    fi

    if [[ $REPOSITORY == "" ]]; then
        continue
    fi

    echo "Auditing repository $OWNER/$REPOSITORY"
    # Create audit_owner_repo.csv file
    AUDIT_FILE="${AUDIT_FOLDER}/audit_${OWNER}_${REPOSITORY}.csv"

    # Catch repo details
    # https://cli.github.com/manual/gh_api
    DETAILS_FILE="${AUDIT_FOLDER}/details_${OWNER}_${REPOSITORY}.json"
    gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/${OWNER}/${REPOSITORY}" > "${DETAILS_FILE}"

    if [ ! -f "${DETAILS_FILE}" ]; then
        echo "Error getting details for repository ${OWNER}/${REPOSITORY}"
        continue
    fi

    # Get default branch from json .default_branch
    DEFAULT_BRANCH=$(jq -r '.default_branch' "${DETAILS_FILE}")
    echo "Default Branch: ${DEFAULT_BRANCH}"

    # Adjust QUERY_PRS
    # 1. Replace <DEFAULT> with the default branch
    # 2. Remove quotes
    # 3. Add repo:owner/repo
    QUERY_PRS=${QUERY_PRS//<DEFAULT>/${DEFAULT_BRANCH}}
    QUERY_PRS=${QUERY_PRS//\"/}
    QUERY_PRS="repo:${OWNER}/${REPOSITORY}+${QUERY_PRS}"
    echo "Query: ${QUERY_PRS}"

    # PRs Analyze
    echo "id,number,title,html_url,user.login,pull_request.merged_at,pull_request.url" > "${AUDIT_FILE}"
    
    # GitHub CLI Search Issues and Pull Requests
    # https://docs.github.com/pt/rest/search/search?apiVersion=2022-11-28#search-issues-and-pull-requests

    gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        --paginate \
        "/search/issues?q=${QUERY_PRS}" > "${AUDIT_FOLDER}/prs_${OWNER}_${REPOSITORY}.json"

    # Analytiz .[]items 
    # Fields: id, number, title, html_url, user.login, pull_request.merged_at, body, pull_request.url
    # Add to CSV
    jq -r '.items[] | [.id, .number, .title, .html_url, .user.login, .pull_request.merged_at, .pull_request.url] | @csv' "${AUDIT_FOLDER}/prs_${OWNER}_${REPOSITORY}.json" >> "${AUDIT_FILE}"

    # QTY
    echo "Total PRs: $(wc -l < "${AUDIT_FILE}")"

    # Get Pull Request API

    # Create folder $AUDIT_FOLDER/$OWNER_$REPOSITORY
    if [ ! -d "${AUDIT_FOLDER}/${OWNER}_${REPOSITORY}" ]; then
        mkdir "${AUDIT_FOLDER}/${OWNER}_${REPOSITORY}"
    fi

    # For each PR, get the PR details
    PR_URL_LIST=$(jq -r '.items[] | .pull_request.url' "${AUDIT_FOLDER}/prs_${OWNER}_${REPOSITORY}.json")
    
    # Using get_pr_details_from_url and xargs
    echo "${PR_URL_LIST}" | xargs -n 1 -P 10 -I {} bash -c "get_pr_details_from_url {}"

    echo "---"
done < "${FILE}"
