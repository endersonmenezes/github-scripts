#!/bin/bash

###############################################################################
# Azure DevOps Token Test Tool
#
# Author: Enderson Menezes
# Created: 2025-04-15
# Updated: 2025-04-15
#
# Description:
#   This script tests the validity of an Azure DevOps Personal Access Token (PAT)
#   by attempting to connect to the Azure DevOps API and a specific NuGet feed.
#   It checks if the token can authenticate and retrieve project information
#   and access the NuGet feed index.
#
# Usage: bash 20-test-azure-devops-token.sh <token> [organization] [project]
#
# Parameters:
#   - token: Azure DevOps Personal Access Token (PAT)
#   - organization: Azure DevOps organization name (optional, defaults to DEFAULT_ORG)
#   - project: Azure DevOps project name (optional, defaults to DEFAULT_PROJECT)
#
# Dependencies:
#   - curl: Used for making HTTP requests to the Azure DevOps API.
#   - jq: Used for parsing JSON responses from the API.
#   - functions.sh: Contains common utility functions (audit_file, is_gh_installed).
###############################################################################

# Read Common Functions
source functions.sh

# Verify GH is installed (Although not directly used for Azure, it's part of the standard script setup)
# is_gh_installed # Commented out as GH CLI is not strictly needed for this script

# Create a SHA256 of the file for audit (Define SHA256 variable)
audit_file

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Configuration ---
DEFAULT_ORG="your_organization" # Replace with your actual default org if desired
DEFAULT_PROJECT="your_project" # Replace with your actual default project if desired
# This URL points to the NuGet v3 service index for the specified feed.
# It's used here to test connectivity and authentication to the feed.

# --- Helper Functions ---

# Function: usage
# Description: Displays help message explaining how to use the script and exits.
usage() {
  echo -e "${YELLOW}Usage:${NC} $0 <token> [organization] [project]"
  echo -e "  ${YELLOW}token${NC}        - Azure DevOps Personal Access Token (PAT)"
  echo -e "  ${YELLOW}organization${NC} - Azure DevOps organization name (default: ${DEFAULT_ORG})"
  echo -e "  ${YELLOW}project${NC}      - Azure DevOps project name (default: ${DEFAULT_PROJECT})"
  exit 1
}

# Function: check_jq
# Description: Checks if the 'jq' command-line JSON processor is installed. Exits if not found.
check_jq() {
  if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed. Please install jq to parse JSON responses.${NC}"
    echo -e "${YELLOW}Example installation (Debian/Ubuntu): sudo apt-get update && sudo apt-get install jq${NC}"
    echo -e "${YELLOW}Example installation (macOS): brew install jq${NC}"
    exit 1
  fi
}

# --- Main Script ---

# Validate required arguments
if [ -z "$1" ]; then
  echo -e "${RED}Error: Token is required${NC}"
  usage
fi

# Assign arguments to variables, using defaults if not provided
TOKEN="$1"
ORG="${2:-$DEFAULT_ORG}"
PROJECT="${3:-$DEFAULT_PROJECT}" # Read project from 3rd arg or use default

# Construct the NuGet feed URL based on the organization and project
NUGET_FEED_URL="https://${ORG}.pkgs.visualstudio.com/_packaging/${PROJECT}/nuget/v3/index.json"

# Ensure jq is available before proceeding
check_jq

echo -e "${YELLOW}Starting Azure DevOps connection tests for organization: ${ORG}${NC}"

# Create a temporary file to store API responses
RESPONSE_FILE=$(mktemp)
# Ensure the temporary file is removed when the script exits (success or failure)
trap 'rm -f "$RESPONSE_FILE"' EXIT

# Flag to track the overall success of all tests
all_tests_passed=true

# --- Test 1: Fetching Projects List ---
echo -e "\n${YELLOW}[Test 1/2] Fetching projects list...${NC}"
# Construct the API URL for listing projects
projects_url="https://dev.azure.com/${ORG}/_apis/projects?api-version=6.0"
echo -e "  ${YELLOW}API URL:${NC} ${projects_url}"
# Execute curl command to fetch projects, storing the HTTP status code
http_status_projects=$(curl --silent --show-error --output "$RESPONSE_FILE" --write-out "%{http_code}" --user ":$TOKEN" "$projects_url")

# Check if the API call was successful (HTTP status 200)
if [ "$http_status_projects" -eq 200 ]; then
  echo -e "  ${GREEN}Project list connection successful! (Status: $http_status_projects)${NC}"
  echo -e "  ${YELLOW}Projects found:${NC}"
  # Use jq to parse the JSON response and list project names
  # Check if the 'value' array exists and is not empty before trying to parse
  if jq -e '.value | length > 0' "$RESPONSE_FILE" > /dev/null; then
      # Extract and print each project name, indented with '- '
      jq -r '.value[].name | select(length > 0)' "$RESPONSE_FILE" | sed 's/^/  - /'
  else
      # Handle cases where no projects are found or the response format is unexpected
      echo -e "  ${YELLOW}No projects found or unable to parse response.${NC}"
  fi
else
  # Handle API call failure
  echo -e "  ${RED}Project list connection failed! (Status: $http_status_projects)${NC}"
  echo -e "  ${RED}Error details:${NC}"
  # Try to pretty-print the error response if it's JSON, otherwise print the raw response
  if jq '.' "$RESPONSE_FILE" 2>/dev/null; then
    echo # Add newline for better formatting if jq succeeded
  else
    cat "$RESPONSE_FILE"
    echo # Add newline
  fi
  # Mark the overall test status as failed
  all_tests_passed=false
fi

# --- Test 2: Checking NuGet Feed Connection ---
echo -e "\n${YELLOW}[Test 2/2] Checking NuGet feed index connection...${NC}"
echo -e "  ${YELLOW}Feed Index URL:${NC} ${NUGET_FEED_URL}"
# Execute curl command to fetch the NuGet feed index, storing the HTTP status code
http_status_nuget=$(curl --silent --show-error --output "$RESPONSE_FILE" --write-out "%{http_code}" --user ":$TOKEN" "$NUGET_FEED_URL")

# Check if the API call was successful (HTTP status 200)
if [ "$http_status_nuget" -eq 200 ]; then
  echo -e "  ${GREEN}NuGet feed index connection successful! (Status: $http_status_nuget)${NC}"
  # Note: The index.json lists API resources, not packages directly.
  # This test primarily confirms authentication and connectivity to the feed endpoint.
  # Optional: Uncomment below to list available resource types from the index
  # echo -e "  ${YELLOW}Available NuGet resources (types):${NC}"
  # jq -r '.resources[]."@type"' "$RESPONSE_FILE" | sed 's/^/  - /' || echo -e "  ${RED}Error parsing NuGet feed index response.${NC}"
else
  # Handle API call failure
  echo -e "  ${RED}NuGet feed index connection failed! (Status: $http_status_nuget)${NC}"
  echo -e "  ${RED}Error details:${NC}"
  # Try to pretty-print the error response if it's JSON, otherwise print the raw response
  if jq '.' "$RESPONSE_FILE" 2>/dev/null; then
      echo # Add newline for better formatting if jq succeeded
  else
      cat "$RESPONSE_FILE"
      echo # Add newline
  fi
  # Mark the overall test status as failed
  all_tests_passed=false
fi

# --- Final Summary ---
echo # Add a newline for clarity before the summary message
# Check the overall status flag and print the final result message
if $all_tests_passed; then
  echo -e "${GREEN}All Azure DevOps connection tests passed successfully!${NC}"
  exit 0 # Exit with success code
else
  echo -e "${RED}One or more Azure DevOps connection tests failed.${NC}"
  exit 1 # Exit with failure code
fi