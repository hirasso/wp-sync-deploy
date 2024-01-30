#!/usr/bin/env bash

# Make this script more strict
set -o errexit
set -o nounset
set -o pipefail

# Deployment to production will only be possible from these two branches
MAIN_BRANCH="master|main"

# Required positional arguments
REMOTE_ENV="$1"

# Load the environment file
loadEnvFile

# Find the deployignore file
DEPLOYIGNORE_FILE=$(findUp ".deployignore" $SCRIPT_DIR)

# Find the tasks file wp-sync-deploy.tasks.php
TASKS_FILE=$(findUp "wp-sync-deploy.tasks.php" $SCRIPT_DIR)

# Normalize variables
LOCAL_HOST=$(trimWhitespace "$LOCAL_HOST")
LOCAL_PROTOCOL=$(trimWhitespace "$LOCAL_PROTOCOL")
LOCAL_HTTP_AUTH=$(trimWhitespace "$LOCAL_HTTP_AUTH")
LOCAL_WEB_ROOT=$(trimWhitespace "$LOCAL_WEB_ROOT")
WP_CONTENT_DIR=$(trimWhitespace "$WP_CONTENT_DIR")
WP_CORE_DIR=$(trimWhitespace "$WP_CORE_DIR")
WP_THEME=$(trimWhitespace "$WP_THEME")

# Set variables based on provided environment (production or staging)
case $REMOTE_ENV in

production)
    REMOTE_HOST=$(trimWhitespace "$PROD_HOST")
    REMOTE_PROTOCOL=$(trimWhitespace "$PROD_PROTOCOL")
    REMOTE_HTTP_AUTH=$(trimWhitespace "$PROD_HTTP_AUTH")
    REMOTE_SSH=$(trimWhitespace "$PROD_SSH")
    REMOTE_WEB_ROOT=$(trimWhitespace "$PROD_WEB_ROOT")
    REMOTE_PHP_BINARY=$(trimWhitespace "$PROD_PHP_BINARY")
    ;;

staging)
    REMOTE_HOST=$(trimWhitespace "$STAG_HOST")
    REMOTE_PROTOCOL=$(trimWhitespace "$STAG_PROTOCOL")
    REMOTE_HTTP_AUTH=$(trimWhitespace "$STAG_HTTP_AUTH")
    REMOTE_SSH=$(trimWhitespace "$STAG_SSH")
    REMOTE_WEB_ROOT=$(trimWhitespace "$STAG_WEB_ROOT")
    REMOTE_PHP_BINARY=$(trimWhitespace "$STAG_PHP_BINARY")
    ;;

*)
    logError "Please provide the remote environment (production or staging)"
    ;;
esac

# Prepare variables for printing
PRETTY_LOCAL_ENV=$(printf "${BOLD}local${NORMAL}")
PRETTY_LOCAL_HOST=$(printf "${BOLD}$LOCAL_HOST${NORMAL}")
PRETTY_REMOTE_ENV=$(printf "${BOLD}$REMOTE_ENV${NORMAL}")
PRETTY_REMOTE_HOST=$(printf "${BOLD}$REMOTE_HOST${NORMAL}")

# Validate required variables
test -z "$LOCAL_WEB_ROOT" && logError "LOCAL_WEB_ROOT is not defined"
test -z "$REMOTE_WEB_ROOT" && logError "REMOTE_WEB_ROOT is not defined"
test -z "$WP_CONTENT_DIR" && logError "WP_CONTENT_DIR is not defined"
test -z "$WP_CORE_DIR" && logError "WP_CORE_DIR is not defined"
test -z "$REMOTE_SSH" && logError "REMOTE_SSH is not defined"
test -z "$REMOTE_HOST" && logError "REMOTE_HOST is not defined"
test -z "$REMOTE_PROTOCOL" && logError "REMOTE_PROTOCOL is not defined"

# Normalize paths
LOCAL_WEB_ROOT=$(normalizePath $LOCAL_WEB_ROOT)
REMOTE_WEB_ROOT=$(normalizePath $REMOTE_WEB_ROOT)
WP_CONTENT_DIR=$(trimLeadingSlashes $(normalizePath $WP_CONTENT_DIR))
WP_CORE_DIR=$(trimLeadingSlashes $(normalizePath $WP_CORE_DIR))

# Construct and normalize URLs
LOCAL_URL=$(normalizeUrl "$LOCAL_PROTOCOL://$LOCAL_HOST")
REMOTE_URL=$(normalizeUrl "$REMOTE_PROTOCOL://$REMOTE_HOST")