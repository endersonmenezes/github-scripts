#!/usr/bin/env bash

##
# Author: Enderson Menezes
# Created: 2025-03-07
# Description: This script will audit a github repository getting all information from it.
# Usage: bash 17-github-new-audit-repo.sh
##

# Set Environment
set -e

REPO="$1"
DATE_START="$2"
DATE_END="$3"

# Validate parameters
if [[ -z "$REPO" ]]; then
  echo "Repository is required"
  exit 1
fi

if [[ -z "$DATE_START" ]]; then
  echo "Date start is required"
  exit 1
fi

if [[ -z "$DATE_END" ]]; then
  echo "Date end is required"
  exit 1
fi

# Validate repo are owner/repo
if [[ $(echo $REPO | grep -c "/") -ne 1 ]]; then
  echo "Repository must be in the format owner/repo"
  exit 1
fi

# Validate date are in the format YYYY-MM-DD
if [[ $(echo $DATE_START | grep -c "^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}$") -ne 1 ]]; then
  echo "Date start must be in the format YYYY-MM-DD"
  exit 1
fi

if [[ $(echo $DATE_END | grep -c "^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}$") -ne 1 ]]; then
  echo "Date end must be in the format YYYY-MM-DD"
  exit 1
fi



NORMALIZE_REPO_NAME_KEBAB=$(echo $REPO | tr '[:upper:]' '[:lower:]' | tr '/' '-')
FILE_PREFIX="audit-$NORMALIZE_REPO_NAME_KEBAB-$DATE_START-$DATE_END"
FILE_PREFIX_WITHOUT_DATE="audit-$NORMALIZE_REPO_NAME_KEBAB"

# Intro
echo "Auditing GitHub repository: $REPO"

# https://docs.github.com/en/rest/reference/repos#get-a-repository
echo "-> Getting repository information"
# verify file exists
if [[ -f "${FILE_PREFIX_WITHOUT_DATE}-info.json" ]]; then
  echo "--> File info.json already exists"
else
  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    /repos/$REPO > "${FILE_PREFIX_WITHOUT_DATE}-info.json"
fi
DEFAULT_BRANCH=$(jq -r '.default_branch' "${FILE_PREFIX_WITHOUT_DATE}-info.json")

# https://docs.github.com/en/rest/actions/workflows?apiVersion=2022-11-28#list-repository-workflows
echo "-> Getting repository workflows"
# verify file exists
if [[ -f "${FILE_PREFIX_WITHOUT_DATE}-workflows.json" ]]; then
  echo "--> File workflows.json already exists"
else
  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    /repos/$REPO/actions/workflows > "${FILE_PREFIX_WITHOUT_DATE}-workflows.json"
fi
WORKFLOWS_IDS=$(jq -r '.workflows[].id' ${FILE_PREFIX_WITHOUT_DATE}-workflows.json)

# https://docs.github.com/en/rest/actions/workflow-runs?apiVersion=2022-11-28#list-workflow-runs-for-a-repository
echo "-> Getting repository workflow runs"
WORKFLOW_QUERY="status=completed&per_page=100&created=${DATE_START}T00:00:00Z..${DATE_END}T23:59:59Z"
# verify file exists
if [[ -f "${FILE_PREFIX}-runs.json" ]]; then
  echo "--> File runs.json already exists"
else
  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    --paginate \
    "/repos/$REPO/actions/runs?$WORKFLOW_QUERY" > "${FILE_PREFIX}-runs.json"
fi

RUNS_IDS=$(jq -r '.workflow_runs[] | .id' ${FILE_PREFIX}-runs.json)
echo "We have $(echo $RUNS_IDS | wc -w) runs"

# https://docs.github.com/en/rest/actions/workflow-runs?apiVersion=2022-11-28#get-the-review-history-for-a-workflow-run
echo "-> Getting repository workflow runs reviews"
for RUN_ID in $RUNS_IDS; do
  echo "--> Getting approvals for run: $RUN_ID"
  # Verify file exists
  if [[ -f "${FILE_PREFIX_WITHOUT_DATE}-reviews_$RUN_ID.json" ]]; then
    echo "---> File reviews_$RUN_ID.json already exists"
  else
    URL="/repos/$REPO/actions/runs/$RUN_ID/approvals"
    # echo "---> URL: $URL"
    gh api \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$URL" > "${FILE_PREFIX_WITHOUT_DATE}-reviews_$RUN_ID.json"
  fi
done

# Mount the final report
echo "-> Generating report"
# Verify all files ${FILE_PREFIX_WITHOUT_DATE}-reviews_$RUN_ID.json exists to catch all RUN_ID
FILES=$(find . -name "${FILE_PREFIX_WITHOUT_DATE}-reviews_*.json")
ALL_RUN_IDS=$(echo "$FILES" | sed 's/[^0-9 ]//g')
echo "We have $(echo "$ALL_RUN_IDS" | wc -w) runs with reviews"
echo "workflow_id,workflow_run,workflow_name,run_name,approval_count,approval_users,url,all_approvals_are_same" > report.csv
function add_line_to_csv(){
  RUN_ID="$1"
  NORMALIZE_REPO_NAME_KEBAB=$(echo "$REPO" | tr '[:upper:]' '[:lower:]' | tr '/' '-')
  FILE_PREFIX="audit-${NORMALIZE_REPO_NAME_KEBAB}-${DATE_START}-${DATE_END}"
  FILE_PREFIX_WITHOUT_DATE="audit-${NORMALIZE_REPO_NAME_KEBAB}"
  WORKFLOW_ID=$(jq -r --arg rid "$RUN_ID" '.workflow_runs[] | select(.id == ($rid|tonumber)) | .workflow_id' "${FILE_PREFIX}-runs.json")
  WORKFLOW_NAME=$(jq -r --arg wid "$WORKFLOW_ID" '.workflows[] | select(.id == ($wid|tonumber)) | .name' "${FILE_PREFIX_WITHOUT_DATE}-workflows.json")
  RUN_NAME=$(jq -r --arg rid "$RUN_ID" '.workflow_runs[] | select(.id == ($rid|tonumber)) | .display_title' "${FILE_PREFIX}-runs.json")
  APPROVAL_COUNT=$(jq -r '. | length' "${FILE_PREFIX_WITHOUT_DATE}-reviews_${RUN_ID}.json")
  APPROVAL_USERS=$(jq -r '.[].user.login' "${FILE_PREFIX_WITHOUT_DATE}-reviews_${RUN_ID}.json" | sort | uniq | paste -sd';' -)
  URL=$(jq -r --arg rid "$RUN_ID" '.workflow_runs[] | select(.id == ($rid|tonumber)) | .html_url' "${FILE_PREFIX}-runs.json")
  ALL_APPROVALS_ARE_SAME=$(jq -r '.[].user.login' "${FILE_PREFIX_WITHOUT_DATE}-reviews_${RUN_ID}.json" | sort | uniq | wc -l)
  echo "${WORKFLOW_ID},${RUN_ID},${WORKFLOW_NAME},${RUN_NAME},${APPROVAL_COUNT},${APPROVAL_USERS},${URL},${ALL_APPROVALS_ARE_SAME}" >> report.csv
}
export -f add_line_to_csv
export REPO
export DATE_START
export DATE_END
PARALLEL_NUM=16
# use xargs to process all files in parallel
echo "$ALL_RUN_IDS" | xargs -n 1 -P "$PARALLEL_NUM" -I {} bash -c 'add_line_to_csv "{}"'
echo "Report generated: report.csv"
