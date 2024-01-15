#!/usr/bin/env bash

# Make this script more strict
set -o errexit
set -o nounset
set -o pipefail

# Font Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE="\033[0;34m"
NC='\033[0m' # No Color

# Font styles
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# Deployment to production will only be possible from these two branches
MAIN_BRANCH="master|main"

# Required positional arguments
REMOTE_ENV="$1"

# Find the closest wp-sync-deploy.env file
ENV_FILE=$(findUp "wp-sync-deploy.env" $SCRIPT_DIR)
[ -z "$ENV_FILE" ] && logError "No wp-sync-deploy.env file found, exiting..."

# Make env vars available everywhere
# @see https://stackoverflow.com/a/30969768/586823
set -o allexport
source $ENV_FILE
set +o allexport

# Set SSH paths based on provided environment (production/staging)
case $REMOTE_ENV in

production)
    # Define your production vars
    export REMOTE_HOST=$PROD_HOST
    export REMOTE_PROTOCOL=$PROD_PROTOCOL
    export REMOTE_HTTP_AUTH=$PROD_HTTP_AUTH
    export REMOTE_SSH=$PROD_SSH
    export REMOTE_WEB_ROOT=$PROD_WEB_ROOT
    export REMOTE_PHP_BINARY=$PROD_PHP_BINARY
    ;;

staging)
    # Define your staging vars
    export REMOTE_HOST=$STAG_HOST
    export REMOTE_PROTOCOL=$STAG_PROTOCOL
    export REMOTE_HTTP_AUTH=$STAG_HTTP_AUTH
    export REMOTE_SSH=$STAG_SSH
    export REMOTE_WEB_ROOT=$STAG_WEB_ROOT
    export REMOTE_PHP_BINARY=$STAG_PHP_BINARY
    ;;

*)
    logError "Please provide the remote environment (production or staging)"
    ;;
esac

# Prepare variables for printing
PRETTY_LOCAL_ENV=$(printf "${BOLD}local${NORMAL}")
PRETTY_REMOTE_ENV=$(printf "${BOLD}$REMOTE_ENV${NORMAL}")

# Validate required variables
test -z "$LOCAL_WEB_ROOT" && logError "LOCAL_WEB_ROOT is not defined"
test -z "$REMOTE_WEB_ROOT" && logError "REMOTE_WEB_ROOT is not defined"
test -z "$WP_CONTENT_DIR" && logError "WP_CONTENT_DIR is not defined"
test -z "$WP_CORE_DIR" && logError "WP_CORE_DIR is not defined"
test -z "$REMOTE_SSH" && logError "REMOTE_SSH is not defined"
test -z "$REMOTE_HOST" && logError "REMOTE_HOST is not defined"
test -z "$REMOTE_PROTOCOL" && logError "REMOTE_PROTOCOL is not defined"

# Normalize paths from the .env file
LOCAL_WEB_ROOT=$(normalizePath $LOCAL_WEB_ROOT)
REMOTE_WEB_ROOT=$(normalizePath $REMOTE_WEB_ROOT)
WP_CONTENT_DIR=$(trimLeadingSlash $(normalizePath $WP_CONTENT_DIR))
WP_CORE_DIR=$(trimLeadingSlash $(normalizePath $WP_CORE_DIR))