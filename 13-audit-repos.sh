#!/usr/bin/env bash

###############################################################################
# GitHub Repository Audit Tool
#
# Author: Enderson Menezes
# Created: 2024-08-12
# Updated: 2025-03-14
#
# Description:
#   This script performs a comprehensive audit of GitHub repositories based on
#   a CSV configuration file. It collects repository details, pull requests,
#   reviews, workflow runs, and other metadata for compliance and security analysis.
#
# Input File Format (13-audit-repos.csv):
#   owner,repo,query_prs
#
# Usage: bash 13-audit-repos.sh
###############################################################################

# Read Common Functions
source functions.sh

# Verify GH is installed
is_gh_installed

# Create a SHA256 of the file for audit (Define SHA256 varible)
audit_file

## Read a CSV file (owner-repo,team,permission) (Define FILE variable)
read_config_file

# Args
PARALLEL_JOBS=5

# Function to wrapper github api
function github_api_wrapper(){
  # Use local variables to avoid conflicts
  local ROUTE
  local FILE_TO_SAVE
  local RATE_LIMIT
  local RATE_LIMIT_REMAINING
  local RATE_LIMIT_RESET
  local NOW
  local NEED_TO_SLEEP
  local RELATIVE_MINUTES

  # Variables
  ROUTE=$1
  FILE_TO_SAVE=$2

  # Analyze rate limit
  RATE_LIMIT=$(gh api /rate_limit)
  RATE_LIMIT_REMAINING=$(echo "${RATE_LIMIT}" | jq '.resources.core.remaining')
  RATE_LIMIT_RESET=$(echo "${RATE_LIMIT}" | jq '.resources.core.reset')
  # echo "API rate limit remaining: ${RATE_LIMIT_REMAINING} - Reset: ${RATE_LIMIT_RESET}"
  if [[ "${RATE_LIMIT_REMAINING}" -lt 100 ]]; then
      NOW=$(date +%s)
      NEED_TO_SLEEP=$((RATE_LIMIT_RESET - NOW))
      RELATIVE_MINUTES=$((NEED_TO_SLEEP / 60))
      echo "API rate limit is below 100. Sleeping until reset, will be back at: ${RATE_LIMIT_RESET} which is in ${RELATIVE_MINUTES} minutes"
      sleep "${NEED_TO_SLEEP}"
      NOW=$(date +%s)
      echo "${NOW}" > "${TIMESTAMP_FILE}"
      continue
  fi

  gh api \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      --paginate \
      "${ROUTE}" > "${FILE_TO_SAVE}"
}
export -f github_api_wrapper

# Function to get details from PR
get_pr_details_from_url(){
  PR_URL=$1
  PR_NUMBER=$(cut -d'/' -f8 <<< "${PR_URL}")
  OWNER=$(cut -d'/' -f5 <<< "${PR_URL}")
  REPOSITORY=$(cut -d'/' -f6 <<< "${PR_URL}")

  # Get PR details
  DETAILS_FILE="${AUDIT_FOLDER}/${OWNER}_${REPOSITORY}/pr_${PR_NUMBER}.json"
  github_api_wrapper "${PR_URL}" "${AUDIT_FOLDER}/${OWNER}_${REPOSITORY}/pr_${PR_NUMBER}.json"

  # Status URL .statuses_url
  STATUS_URL=$(jq -r '.statuses_url' "${AUDIT_FOLDER}/${OWNER}_${REPOSITORY}/pr_${PR_NUMBER}.json")
  # echo "Getting PR status for PR ${PR_NUMBER} on ${OWNER}/${REPOSITORY}"
  github_api_wrapper "${STATUS_URL}" "${AUDIT_FOLDER}/${OWNER}_${REPOSITORY}/pr_${PR_NUMBER}_status.json"

  # Get Review from PR
  # /repos/{owner}/{repo}/pulls/{pull_number}/reviews
  # echo "Getting PR reviews for PR ${PR_NUMBER} on ${OWNER}/${REPOSITORY}"
  github_api_wrapper "/repos/${OWNER}/${REPOSITORY}/pulls/${PR_NUMBER}/reviews" "${AUDIT_FOLDER}/${OWNER}_${REPOSITORY}/pr_${PR_NUMBER}_reviews.json"

  # Get MERGE_COMMIT_SHA from PR
  MERGE_COMMIT_SHA=$(jq -r '.merge_commit_sha' "${DETAILS_FILE}")

  # Use MERGE_COMMIT_SHA to get run jobs workflows
  # echo "Getting jobs runs for PR ${PR_NUMBER} on ${OWNER}/${REPOSITORY}"
  github_api_wrapper "/repos/${OWNER}/${REPOSITORY}/actions/runs?head_sha=${MERGE_COMMIT_SHA}" "${PRS_FOLDER}/pr_${PR_NUMBER}_jobs_runs.json"

}
export -f get_pr_details_from_url

# Specific Config File
if [[ $(head -n 1 $FILE) != "owner,repo,query_prs" ]]; then
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
echo "Reading file $FILE"
while IFS=, read -r OWNER REPOSITORY QUERY_PRS; do
  # Ignore Cases ----
  if [[ $OWNER == "owner" ]]; then
      continue
  fi

  if [[ $REPOSITORY == "" ]]; then
      continue
  fi
  # Ignore Cases ----

  echo "Auditing repository $OWNER/$REPOSITORY"
  # Create audit_owner_repo.csv file
  AUDIT_FILE="${AUDIT_FOLDER}/audit_${OWNER}_${REPOSITORY}.csv"
  WORKFLOW_AUDIT_FILE="${AUDIT_FOLDER}/workflows_${OWNER}_${REPOSITORY}.csv"

  # Catch repo details
  # https://cli.github.com/manual/gh_api
  DETAILS_FILE="${AUDIT_FOLDER}/details_${OWNER}_${REPOSITORY}.json"
  github_api_wrapper "/repos/${OWNER}/${REPOSITORY}" "${DETAILS_FILE}"

  # Validate if DETAILS_FILE exists
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
  echo "id,number,title,html_url,user.login,pull_request.merged_at,pull_request.url,merge_commit_sha,approved_by" > "${AUDIT_FILE}"
  
  # WorkFlow Analyze
  echo "id,name,head_branch,head_sha,path,display_title,status,conclusion" > "${WORKFLOW_AUDIT_FILE}"

  # Get PRs
  # https://docs.github.com/pt/rest/search/search?apiVersion=2022-11-28#search-issues-and-pull-requests
  
  github_api_wrapper "/search/issues?q=${QUERY_PRS}" "${AUDIT_FOLDER}/prs_${OWNER}_${REPOSITORY}.json"

  # Fields: id, number, title, html_url, user.login, pull_request.merged_at, body, pull_request.url
  jq -r '.items[] | [.id, .number, .title, .html_url, .user.login, .pull_request.merged_at, .pull_request.url] | @csv' "${AUDIT_FOLDER}/prs_${OWNER}_${REPOSITORY}.json" >> "${AUDIT_FILE}"

  # QTY
  echo "Total PRs: $(($(wc -l < "${AUDIT_FILE}") - 1))"

  # Create folder $AUDIT_FOLDER/$OWNER_$REPOSITORY
  PRS_FOLDER="${AUDIT_FOLDER}/${OWNER}_${REPOSITORY}"
  if [ ! -d $PRS_FOLDER ]; then
      mkdir $PRS_FOLDER
  fi
  export PRS_FOLDER

  # For each PR, get the PR details
  PR_URL_LIST=$(jq -r '.items[] | .pull_request.url' "${AUDIT_FOLDER}/prs_${OWNER}_${REPOSITORY}.json")
  
  # Using get_pr_details_from_url and xargs
  echo "Getting PR details for ${OWNER}/${REPOSITORY}"
  echo "${PR_URL_LIST}" | xargs -n 1 -P ${PARALLEL_JOBS} -I {} bash -c "get_pr_details_from_url {}"

  # Catch details file and list merge_commit_sha
  REGEX="pr_([0-9]+).json"
  DETAILS_FILES=$(ls ${PRS_FOLDER}/pr_*.json | grep -E "${REGEX}")
  for DETAILS_FILE in $DETAILS_FILES; do
    MERGE_COMMIT_SHA=""
    FILE_NAME=$(basename "${DETAILS_FILE}")
    PR_NUMBER_WITH_EXTENSION=$(cut -d'_' -f2 <<< "${FILE_NAME}")
    PR_NUMBER=$(cut -d'.' -f1 <<< "${PR_NUMBER_WITH_EXTENSION}")

    # Catch merge_commit_sha
    MERGE_COMMIT_SHA=$(jq -r '.merge_commit_sha' "${DETAILS_FILE}")
    # echo "PR ${PR_NUMBER} Merge Commit SHA: ${MERGE_COMMIT_SHA}"

    # Catch review file and list approved reviews
    REVIEW_FILE="${PRS_FOLDER}/pr_${PR_NUMBER}_reviews.json"
    # echo "Getting approved reviews for PR ${PR_NUMBER} on ${OWNER}/${REPOSITORY}"
    APPROVALS=$(jq -r '.[] | select(.state == "APPROVED") | .user.login' "${REVIEW_FILE}" | sort | uniq | paste -sd ";")
    #echo "Approved by: ${APPROVALS}"

    # Send data to workflows csv
    jq -r '.workflow_runs[] | [.id, .name, .head_branch, .head_sha, .path, .display_title, .status, .conclusion] | @csv' "${PRS_FOLDER}/pr_${PR_NUMBER}_jobs_runs.json" >> "${AUDIT_FOLDER}/workflows_${OWNER}_${REPOSITORY}.csv"

    # Add aproved_by to audit file
    PR_URL=$(jq -r '.url' "${DETAILS_FILE}")
    NEW_LINE_TO_ADD="\"${MERGE_COMMIT_SHA}\",\"${APPROVALS}\""
    sed -i "s|${PR_URL}\"|${PR_URL}\",${NEW_LINE_TO_ADD}|g" "${AUDIT_FILE}"
    
  done

  echo "---"
done < "${FILE}"
