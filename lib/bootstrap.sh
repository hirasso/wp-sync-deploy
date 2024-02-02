#!/usr/bin/env bash

# Make this script more strict
set -o errexit
set -o nounset
set -o pipefail

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
LOCAL_HTTP_AUTH=$(trimWhitespace "${LOCAL_HTTP_AUTH:-}")
LOCAL_ROOT_DIR=$(trimWhitespace "$LOCAL_ROOT_DIR")
PUBLIC_DIR=$(trimWhitespace "${PUBLIC_DIR:-}")
WP_CONTENT_DIR=$(trimWhitespace "$WP_CONTENT_DIR")
WP_CORE_DIR=$(trimWhitespace "$WP_CORE_DIR")

# Deployment to production will only be possible from these two branches
PRODUCTION_BRANCH="${PRODUCTION_BRANCH:-master|main}"

# Set variables based on provided environment (production or staging)
case $REMOTE_ENV in

production)
    REMOTE_HOST=$(trimWhitespace "$PROD_HOST")
    REMOTE_PROTOCOL=$(trimWhitespace "$PROD_PROTOCOL")
    REMOTE_HTTP_AUTH=$(trimWhitespace "${PROD_HTTP_AUTH:-}")
    REMOTE_SSH=$(trimWhitespace "$PROD_SSH")
    REMOTE_ROOT_DIR=$(trimWhitespace "$PROD_ROOT_DIR")
    REMOTE_PHP_BINARY=$(trimWhitespace "${PROD_PHP_BINARY:-php}")
    ;;

staging)
    REMOTE_HOST=$(trimWhitespace "$STAG_HOST")
    REMOTE_PROTOCOL=$(trimWhitespace "$STAG_PROTOCOL")
    REMOTE_HTTP_AUTH=$(trimWhitespace "${STAG_HTTP_AUTH:-}")
    REMOTE_SSH=$(trimWhitespace "$STAG_SSH")
    REMOTE_ROOT_DIR=$(trimWhitespace "$STAG_ROOT_DIR")
    REMOTE_PHP_BINARY=$(trimWhitespace "${STAG_PHP_BINARY:-php}")
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
test -z "$LOCAL_ROOT_DIR" && logError "LOCAL_ROOT_DIR is not defined"
test -z "$REMOTE_ROOT_DIR" && logError "REMOTE_ROOT_DIR is not defined"
test -z "$WP_CONTENT_DIR" && logError "WP_CONTENT_DIR is not defined"
test -z "$WP_CORE_DIR" && logError "WP_CORE_DIR is not defined"
test -z "$REMOTE_SSH" && logError "REMOTE_SSH is not defined"
test -z "$REMOTE_HOST" && logError "REMOTE_HOST is not defined"
test -z "$REMOTE_PROTOCOL" && logError "REMOTE_PROTOCOL is not defined"

# Normalize paths
LOCAL_WEB_ROOT=$(normalizePath "${LOCAL_ROOT_DIR}/${PUBLIC_DIR}")
REMOTE_WEB_ROOT=$(normalizePath "${REMOTE_ROOT_DIR}/${PUBLIC_DIR}")
PUBLIC_DIR=$(trimLeadingSlashes $(normalizePath "$PUBLIC_DIR"))
WP_CONTENT_DIR=$(trimLeadingSlashes $(normalizePath "$WP_CONTENT_DIR"))
WP_CORE_DIR=$(trimLeadingSlashes $(normalizePath "$WP_CORE_DIR"))

# Construct and normalize URLs
LOCAL_URL=$(normalizeUrl "${LOCAL_PROTOCOL}://${LOCAL_HOST}")
REMOTE_URL=$(normalizeUrl "${REMOTE_PROTOCOL}://${REMOTE_HOST}")