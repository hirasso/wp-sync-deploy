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

# Fallback for the production branch: master or main
PRODUCTION_BRANCH="${PRODUCTION_BRANCH:-master|main}"

# Set variables based on provided environment (production or staging)
case $REMOTE_ENV in

production)
    REMOTE_HOST=$(trimWhitespace "$PROD_HOST")
    REMOTE_PROTOCOL=$(trimWhitespace "$PROD_PROTOCOL")
    REMOTE_HTTP_AUTH=$(trimWhitespace "${PROD_HTTP_AUTH:-}")
    REMOTE_SSH=$(trimWhitespace "$PROD_SSH")
    REMOTE_SSH_PORT=$(trimWhitespace "${PROD_SSH_PORT:-22}")
    REMOTE_ROOT_DIR=$(trimWhitespace "$PROD_ROOT_DIR")
    REMOTE_PHP_BINARY=$(trimWhitespace "${PROD_PHP_BINARY:-php}")
    DEPLOY_STRATEGY=$(trimWhitespace "${PROD_DEPLOY_STRATEGY:-conservative}")
    REMOTE_ENV_PREFIX="PROD_"
    ;;

staging)
    REMOTE_HOST=$(trimWhitespace "$STAG_HOST")
    REMOTE_PROTOCOL=$(trimWhitespace "$STAG_PROTOCOL")
    REMOTE_HTTP_AUTH=$(trimWhitespace "${STAG_HTTP_AUTH:-}")
    REMOTE_SSH=$(trimWhitespace "$STAG_SSH")
    REMOTE_SSH_PORT=$(trimWhitespace "${STAG_SSH_PORT:-22}")
    REMOTE_ROOT_DIR=$(trimWhitespace "$STAG_ROOT_DIR")
    REMOTE_PHP_BINARY=$(trimWhitespace "${STAG_PHP_BINARY:-php}")
    DEPLOY_STRATEGY=$(trimWhitespace "${STAG_DEPLOY_STRATEGY:-conservative}")
    REMOTE_ENV_PREFIX="STAG_"
    ;;

*)
    logError "Please provide the remote environment (production or staging)"
    ;;
esac

# Store the SSH connection with the port for usage
SSH_CONNECTION="ssh -p $REMOTE_SSH_PORT $REMOTE_SSH"

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
PUBLIC_DIR=$(relativePath $(normalizePath "$PUBLIC_DIR"))
WP_CONTENT_DIR=$(relativePath $(normalizePath "$WP_CONTENT_DIR"))
WP_CORE_DIR=$(relativePath $(normalizePath "$WP_CORE_DIR"))

# Construct and normalize URLs
LOCAL_URL=$(normalizeUrl "${LOCAL_PROTOCOL}://${LOCAL_HOST}")
REMOTE_URL=$(normalizeUrl "${REMOTE_PROTOCOL}://${REMOTE_HOST}")

# Validate the DEPLOY_STRATEGY
if ! [[ "$DEPLOY_STRATEGY" =~ ^(conservative|risky)$ ]]; then
    logError "\$${REMOTE_ENV_PREFIX}DEPLOY_STRATEGY must either be 'conservative' or 'risky'. (provided value: '$DEPLOY_STRATEGY')"
fi