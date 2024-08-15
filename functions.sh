#!/bin/bash

# Functions that can be used in other scripts
# Author: Enderson Menezes
# E-mail: mail@enderson.dev

## SHA Function
# That function will create a SHA256 hash of the file that is being executed

audit_file(){
    FILE_SHA256=$(sha256sum "$0")
    SHA256=$(cut -d' ' -f1 <<< "${FILE_SHA256}")
    echo "Executing a file: $0, with SHA256: ${SHA256}"
}


## Read Config File
# This function will read a CSV File with same name as the script

read_config_file(){
    ## Read a CSV file (owner-repo,team)
    SCRIPT_NAME_WITHOUT_EXTENSION=$(basename "$0" | cut -d'.' -f1)
    FILE="${SCRIPT_NAME_WITHOUT_EXTENSION}.csv"

    # Verify if the file exists
    if [[ ! -f "${FILE}" ]]; then
        echo "The file ${FILE} does not exist."
        exit 1
    fi
}

## Verify GH is installed

is_gh_installed(){
    if ! command -v gh &> /dev/null; then
        echo "The GitHub CLI is not installed."
        exit 1
    fi
}