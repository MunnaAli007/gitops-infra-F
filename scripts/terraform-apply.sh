#!/bin/bash

log() { printf "\e[30;47m %s \e[0m %s\n" "$(echo $1 | tr '[:lower:]' '[:upper:]')" "${@:2}"; }          # $1 uppercase background white
info() { printf "\e[48;5;28m %s \e[0m %s\n" "$(echo $1 | tr '[:lower:]' '[:upper:]')" "${@:2}"; }       # $1 uppercase background green
warn() { printf "\e[48;5;202m %s \e[0m %s\n" "$(echo $1 | tr '[:lower:]' '[:upper:]')" "${@:2}" >&2; }  # $1 uppercase background orange
error() { printf "\e[48;5;196m %s \e[0m %s\n" "$(echo $1 | tr '[:lower:]' '[:upper:]')" "${@:2}" >&2; } # $1 uppercase background red

log START $(date "+%Y-%d-%m %H:%M:%S")
START=$SECONDS

[[ -z $(printenv | grep ^CHDIR=) ]] \
    && { error ABORT CHDIR env variable is required; exit 1; } \
    || log CHDIR $CHDIR
    
# list all TF_VAR_ variables available in enviroment variables
while read line; do
    TF_VAR=$(echo $line | cut -d '=' -f 1)
    VALUE=$(echo $line | cut -d '=' -f 2-)
    log $TF_VAR $VALUE
done < <(printenv | grep ^TF_VAR_)

# https://www.terraform.io/cli/commands/plan
terraform -chdir="$CHDIR" plan -out=terraform.plan
    
# https://www.terraform.io/cli/commands/apply
terraform -chdir="$CHDIR" apply -auto-approve terraform.plan

log END $(date "+%Y-%d-%m %H:%M:%S")
info DURATION $(($SECONDS - $START)) seconds