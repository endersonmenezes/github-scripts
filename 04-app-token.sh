#!/usr/bin/env bash

###############################################################################
# GitHub App Token Generator
#
# Author: Enderson Menezes
# Created: 2024-03-08
# Updated: 2025-03-14
#
# Description:
#   This script reads a CSV file and generates GitHub App tokens using
#   the provided credentials. The tokens can be used for API authentication
#   with elevated permissions.
#
# Input File Format (04-app-token.csv):
#   owner,app_id,app_install_id,file
#
# Usage: bash 04-app-token.sh
###############################################################################

# Read Common Functions
source functions.sh

# Verify GH is installed
is_gh_installed

# Create a SHA256 of the file for audit (Define SHA256 varible)
audit_file

## Read a CSV file (owner-repo,team,permission) (Define FILE variable)
read_config_file

# Specific Config File
if [[ $(head -n 1 $FILE) != "owner,app_id,app_install_id,file" ]]; then
    echo "The file $FILE does not have the correct format."
    exit 1
fi

# Verify last line
if [[ $(tail -n 1 $FILE) != "" ]]; then
    echo "The file $FILE does not have the correct format."
    echo "Adding a blank line at the end of the file..."
    echo "" >> $FILE
fi

# Read line by line
while IFS=, read -r OWNER APP_ID APP_INSTALL_ID FILE_PEM; do
    # Continue on first line
    [ "$OWNER" == "owner" ] && continue

    # Ignore blank line
    [ -z "$OWNER" ] && continue

    echo "Generating token for organization: $OWNER"

    # Generate JWT
    ORGANIZATION=$OWNER
    GITHUB_APP_ID=$APP_ID
    GITHUB_ORG_INSTALL_ID=$APP_INSTALL_ID
    SECURE_FILE=$FILE_PEM
    PEM=$(cat ${SECURE_FILE})
    NOW=$( date +%s )
    IAT="${NOW}"
    EXP=$((${NOW} + 600))
    HEADER_RAW='{"alg":"RS256"}'
    HEADER=$( echo -n "${HEADER_RAW}" | openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n' )
    PAYLOAD_RAW='{"iat":'"${IAT}"',"exp":'"${EXP}"',"iss":'"${GITHUB_APP_ID}"'}'
    PAYLOAD=$( echo -n "${PAYLOAD_RAW}" | openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n' )
    HEADER_PAYLOAD="${HEADER}"."${PAYLOAD}"
    SIGNATURE=$( openssl dgst -sha256 -sign <(echo -n "${PEM}") <(echo -n "${HEADER_PAYLOAD}") | openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n' )
    JWT="${HEADER_PAYLOAD}"."${SIGNATURE}"
    RESPONSE=$(curl -i -X POST -H "Authorization: Bearer ${JWT}" -H "Accept: application/vnd.github.v3+json" https://api.github.com/app/installations/"${GITHUB_ORG_INSTALL_ID}"/access_tokens)
    TOKEN=$( echo "${RESPONSE}" | grep -Po '"token": "\K.*?(?=")' )
    echo "Token for $OWNER: $TOKEN"
done < $FILE
