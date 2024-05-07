#!/bin/bash

log() { printf "\e[30;47m %s \e[0m %s\n" "$(echo $1 | tr '[:lower:]' '[:upper:]')" "${@:2}"; }          # $1 uppercase background white
info() { printf "\e[48;5;28m %s \e[0m %s\n" "$(echo $1 | tr '[:lower:]' '[:upper:]')" "${@:2}"; }       # $1 uppercase background green
warn() { printf "\e[48;5;202m %s \e[0m %s\n" "$(echo $1 | tr '[:lower:]' '[:upper:]')" "${@:2}" >&2; }  # $1 uppercase background orange
error() { printf "\e[48;5;196m %s \e[0m %s\n" "$(echo $1 | tr '[:lower:]' '[:upper:]')" "${@:2}" >&2; } # $1 uppercase background red

usage() {
    echo -ne "\033[0;4musage\033[0m "
    echo "$(basename $0) <directory>"
}

[[ $# -lt 1 || ! -d $1 ]] && { error abort argument error; usage; exit 1; }

CHDIR=$1
log CHDIR "$CHDIR"

# list all TF_VAR_ variables available in enviroment variables
while read line; do
    TF_VAR=$(echo $line | cut -d '=' -f 1)
    VALUE=$(echo $line | cut -d '=' -f 2-)
    log "$TF_VAR" "$VALUE"
done < <(printenv | grep ^TF_VAR_)

# https://www.terraform.io/cli/commands/output
JSON=$(terraform -chdir="$CHDIR" output -json)

while read line; do
    log "$line" $(echo "$JSON" | jq -r ".$line.value")
done < <(echo "$JSON" | jq -r 'keys[]')