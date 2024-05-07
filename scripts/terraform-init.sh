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

[[ -z $(printenv | grep ^S3_BUCKET=) ]] \
    && { error ABORT S3_BUCKET env variable is required; exit 1; } \
    || log S3_BUCKET $S3_BUCKET

[[ -z $(printenv | grep ^CONFIG_KEY=) ]] \
    && { error ABORT CONFIG_KEY env variable is required; exit 1; } \
    || log CONFIG_KEY $CONFIG_KEY

[[ -z $(printenv | grep ^AWS_REGION=) ]] \
    && { error ABORT AWS_REGION env variable is required; exit 1; } \
    || log AWS_REGION $AWS_REGION

# https://www.terraform.io/cli/commands/init
terraform -chdir="$CHDIR" init \
    -input=false \
    -backend=true \
    -backend-config="bucket=$S3_BUCKET" \
    -backend-config="key=$CONFIG_KEY" \
    -backend-config="region=$AWS_REGION" \
    -reconfigure

log END $(date "+%Y-%d-%m %H:%M:%S")
info DURATION $(($SECONDS - $START)) seconds