#!/usr/bin/env bash

##
# Author: Enderson Menezes
# Created: 2024-03-08
# Description: This script delete all teams.
# Usage: bash 08-organization-roles.sh <organization>
##


# Args 
ORGANIZATION=$1
if [ -z "$ORGANIZATION" ]; then
    echo "Please inform the organization name."
    exit 1
fi

# Verify JQ is installed
if ! [ -x "$(command -v jq)" ]; then
    echo "Error: jq is not installed." >&2
    exit 1
fi

FILE_NAME="organization-roles-$ORGANIZATION.json"

# Get Organization Roles
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /orgs/$ORGANIZATION/organization-roles > $FILE_NAME

# Verify Roles Functions

verify_json_file_and_permissions() {
    FILE=$1
    if [ ! -f "$FILE" ]; then
        echo "File $FILE not found."
        exit 1
    fi

    ROLE_NAME=$2
    if [ -z "$ROLE_NAME" ]; then
        echo "Please inform the role name."
        exit 1
    fi

    DESCRIPTION=$3
    if [ -z "$DESCRIPTION" ]; then
        echo "Please inform the description."
        exit 1
    fi

    BASE_ROLE=$4
    if [ -z "$BASE_ROLE" ]; then
        echo "Please inform the base role."
        exit 1
    fi

    PERMISSIONS=$5
    if [ -z "$PERMISSIONS" ]; then
        echo "Please inform the permissions."
        exit 1
    fi

    echo ""
    echo "---"
    echo "Verify role: '$ROLE_NAME' (base: $BASE_ROLE)"
    echo "Description: $DESCRIPTION"

    # Verify if the role exists
    SUPPORT_ROLE=$(jq -r ".roles[] | select(.name == \"$ROLE_NAME\")" $FILE)
    if [ -z "$SUPPORT_ROLE" ]; then
        echo "Role $ROLE_NAME not found."
        echo "Trying to create the role $ROLE_NAME"
        create_org_role "${ROLE_NAME}" "${DESCRIPTION}" "${BASE_ROLE}" "${PERMISSIONS[@]}"
    fi

    # Role ID
    ROLE_ID=$(echo $SUPPORT_ROLE | jq -r ".id")
    if [ -z "$ROLE_ID" ]; then
        echo "Role ID not found."
        exit 1
    fi

    # Update role
    echo "Sync role ${ROLE_NAME}"
    update_organization_role "${ROLE_ID}" "${ROLE_NAME}" "${DESCRIPTION}" "${BASE_ROLE}" "${PERMISSIONS[@]}"


    # Verify if the permissions exists
    for PERMISSION in ${PERMISSIONS[@]}; do
        echo "---> Verify permission $PERMISSION"
        SUPPORT_PERMISSION=$(echo $SUPPORT_ROLE | jq -r ".permissions[] | select(. == \"$PERMISSION\")")
        if [ -z "$SUPPORT_PERMISSION" ]; then
            echo "Permission $PERMISSION not found."
            exit 1
        fi
    done

    # Verify BASE_ROLE is the same
    SUPPORT_BASE_ROLE=$(echo $SUPPORT_ROLE | jq -r ".base_role")
    if [ -z "$SUPPORT_BASE_ROLE" ]; then
        echo "Base Role not found."
        exit 1
    fi
    if [ "$SUPPORT_BASE_ROLE" == "null" ]; then
        SUPPORT_BASE_ROLE="none"
    fi
    if [ "$SUPPORT_BASE_ROLE" != "$BASE_ROLE" ]; then
        echo "Base Role is different."
        echo "Expected: $BASE_ROLE, Found: $SUPPORT_BASE_ROLE"
        exit 1
    fi
}

create_org_role(){
    ROLE_NAME=$1
    if [ -z "$ROLE_NAME" ]; then
        echo "Please inform the role name."
        exit 1
    fi

    DESCRIPTION=$2
    if [ -z "$DESCRIPTION" ]; then
        echo "Please inform the description."
        exit 1
    fi

    BASE_ROLE=$3
    if [ -z "$BASE_ROLE" ]; then
        echo "Please inform the base role."
        exit 1
    fi

    PERMISSIONS=$4
    if [ -z "$PERMISSIONS" ]; then
        echo "Please inform the permissions."
        exit 1
    fi

    permissions=()
    for permission in "${PERMISSIONS[@]}"; do
        permissions+=("-f" "permissions[]=$permission")
    done

    # --- BASE_ROLE
    if [ "$BASE_ROLE" = "none" ]; then
        gh api \
            --method POST \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            /orgs/$ORGANIZATION/organization-roles \
            -f "name=$ROLE_NAME" \
            -f "description=$DESCRIPTION" \
            "${permissions[@]}" > /dev/null
    else
        gh api \
            --method POST \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            /orgs/$ORGANIZATION/organization-roles \
            -f "name=$ROLE_NAME" \
            -f "description=$DESCRIPTION" \
            -f "base_role=$BASE_ROLE" \
            "${permissions[@]}" > /dev/null
    fi
}

update_organization_role(){
    ROLE_ID=$1
    if [ -z "$ROLE_ID" ]; then
        echo "Please inform the role id."
        exit 1
    fi

    ROLE_NAME=$2
    if [ -z "$ROLE_NAME" ]; then
        echo "Please inform the role name."
        exit 1
    fi

    DESCRIPTION=$3
    if [ -z "$DESCRIPTION" ]; then
        echo "Please inform the description."
        exit 1
    fi

    BASE_ROLE=$4
    if [ -z "$BASE_ROLE" ]; then
        echo "Please inform the base role."
        exit 1
    fi

    PERMISSIONS=$5
    if [ -z "$PERMISSIONS" ]; then
        echo "Please inform the permissions."
        exit 1
    fi

    permissions=()
    for permission in "${PERMISSIONS[@]}"; do
        permissions+=("-f" "permissions[]=$permission")
    done

    # --- BASE_ROLE
    if [ "$BASE_ROLE" = "none" ]; then
        gh api \
            --method PATCH \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            /orgs/$ORGANIZATION/organization-roles/$ROLE_ID \
            -f "name=$ROLE_NAME" \
            -f "description=$DESCRIPTION" \
            "${permissions[@]}" > /dev/null
    else
        gh api \
            --method PATCH \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            /orgs/$ORGANIZATION/organization-roles/$ROLE_ID \
            -f "name=$ROLE_NAME" \
            -f "description=$DESCRIPTION" \
            -f "base_role=$BASE_ROLE" \
            "${permissions[@]}" > /dev/null
    fi
}

### - support - ###
NAME="support"
PERMISSIONS=(
    "edit_org_custom_properties_values"
    "manage_organization_ref_rules"
    "read_audit_logs"
    "read_organization_custom_org_role"
    "read_organization_custom_repo_role"
    "write_organization_actions_secrets"
    "write_organization_actions_variables"
    "write_organization_runners_and_runner_groups"
)
DESCRIPTION="Time de foundation que fornece suporte ao Github"
BASE_ROLE="admin"
verify_json_file_and_permissions ${FILE_NAME} ${NAME} "${DESCRIPTION}" "${BASE_ROLE}" "${PERMISSIONS[@]}"

### - access-admin - ###
NAME="access-admin"
PERMISSIONS=(
    "read_audit_logs"
    "read_organization_custom_org_role"
    "read_organization_custom_repo_role"
    "write_organization_custom_org_role"
)
DESCRIPTION="role intended to iam team"
BASE_ROLE="none"
verify_json_file_and_permissions ${FILE_NAME} ${NAME} "${DESCRIPTION}" "${BASE_ROLE}" "${PERMISSIONS[@]}"

### - security-operations - ###
NAME="security-operations"
PERMISSIONS=(
    "manage_organization_ref_rules"
    "read_organization_actions_usage_metrics"
)
DESCRIPTION="Custom role for custom actions that the Built-in role does not understand."
BASE_ROLE="none"
verify_json_file_and_permissions ${FILE_NAME} ${NAME} "${DESCRIPTION}" "${BASE_ROLE}" "${PERMISSIONS[@]}"

### - Platform Mobile Admin - ###
NAME="actions-mobile-admin"
PERMISSIONS=(
    "read_organization_actions_usage_metrics"
)
DESCRIPTION="Custom role for see actions usage metrics"
BASE_ROLE="none"
verify_json_file_and_permissions ${FILE_NAME} ${NAME} "${DESCRIPTION}" "${BASE_ROLE}" "${PERMISSIONS[@]}"


### - Secret Scanning Operations - ###
NAME="secret-scanning-operator"
PERMISSIONS=(
    "view_secret_scanning_alerts"
)
DESCRIPTION="Custom role for see secret scanning alerts"
BASE_ROLE="read"
verify_json_file_and_permissions ${FILE_NAME} ${NAME} "${DESCRIPTION}" "${BASE_ROLE}" "${PERMISSIONS[@]}"



### - Grant to Teams - ###

# Verify '08-organization-roles.csv' exists
if [ ! -f "08-organization-roles.csv" ]; then
    echo "File '08-organization-roles.csv' not found."
    exit 1
fi
echo "✅ File '08-organization-roles.csv' exists."

# Verify the header is organization,team,role
HEADER=$(head -n 1 08-organization-roles.csv)
if [ "$HEADER" != "organization,team,role" ]; then
    echo "The header is not organization,team,role"
    exit 1
fi
echo "✅ The header is organization,team,role."

if [ -n "$(tail -c 1 08-organization-roles.csv)" ]; then
    echo "" >> 08-organization-roles.csv
fi
echo "✅ The file 08-organization-roles.csv is well formatted."

# For any line in the file
while IFS=, read -r CSV_ORG CSV_TEAM CSV_ROLE; do
    if [ "$CSV_ORG" != "$ORGANIZATION" ]; then
        echo "Skipping organization $CSV_ORG"
        continue
    fi

    if [ "$CSV_TEAM" == "team" ]; then
        continue
    fi

    # Catch role id
    ROLE_ID=$(jq -r ".roles[] | select(.name == \"$CSV_ROLE\")" $FILE_NAME | jq -r ".id")

    echo "Granting role $CSV_ROLE to team $CSV_TEAM in organization $CSV_ORG"
    # /orgs/ORG/organization-roles/teams/TEAM_SLUG/ROLE_ID
    ROUTE="/orgs/$ORGANIZATION/organization-roles/teams/$CSV_TEAM/$ROLE_ID"
    gh api \
        -X PUT \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        $ROUTE > /dev/null
    
    echo "✅ Role $CSV_ROLE granted to team $CSV_TEAM in organization $CSV_ORG"
done < 08-organization-roles.csv