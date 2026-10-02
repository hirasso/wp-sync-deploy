#!/usr/bin/env bash

# SYNC your WordPress Database between environments
#
# Please have a look at ./wp-sync-deploy.example.env to see all required variables
#
# COMMANDS:
#
# Sync the database from your production or staging server:
# `vendor/bin/wp-sync-deploy sync <production|staging>`
#
# Sync your local database to the staging server:
# `vendor/bin/wp-sync-deploy sync staging push`
#

# The directory relative to the script
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Source files
source "$SCRIPT_DIR/lib/functions.sh"

# Will be displayed if no arguments are being provided
USAGE_MESSAGE="Usage: https://github.com/hirasso/wp-sync-deploy#synchronise-the-database-between-environments

vendor/bin/wp-sync-deploy sync <production|staging> [push|backup]"

# Exit early if we received no arguments
[ $# -eq 0 ] && logError "$USAGE_MESSAGE"

source "$SCRIPT_DIR/lib/bootstrap.sh"

SYNC_MODE="pull"
[ ! -z "${2+x}" ] && SYNC_MODE="$2"

case $SYNC_MODE in

pull)
  pullDatabase
  ;;
push)
  pushDatabase
  ;;
backup)
  backupDatabase
  ;;
*)
  logError "$USAGE_MESSAGE"
  ;;

esac
