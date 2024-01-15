#!/usr/bin/env bash

# SYNC your WordPress Database between environments
#
# Please have a look at ./wp-sync-deploy.example.env to see all required variables
#
# COMMANDS:
#
# Sync the database from your production or staging server:
# `./wp-sync-deploy/sync.sh <production|staging>`
#
# Sync your local database to the staging server:
# `./wp-sync-deploy/sync.sh staging push`
#

# The directory relative to the script
SCRIPT_DIR=$(realpath $(dirname $0))

# Source files
source "$SCRIPT_DIR/lib/functions.sh"
source "$SCRIPT_DIR/lib/bootstrap.sh"

# Will be displayed if no arguments are being provided
USAGE_MESSAGE="Usage: https://github.com/hirasso/wp-sync-deploy#synchronise-the-database-between-environments

./wp-sync-deploy/sync.sh <sync|deploy> <production|staging> [run] "

# Exit early if we received no arguments
[ $# -eq 0 ] && logError "$USAGE_MESSAGE"

SYNC_MODE="pull"
[ ! -z "${2+x}" ] && SYNC_MODE="$2"

case $SYNC_MODE in

pull)
    pullDatabase
    ;;
push)
    pushDatabase
    ;;
*)
    logError "Usage: sync <production|staging> <pull|push>"
    ;;

esac
