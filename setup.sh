#!/usr/bin/env bash

# SETUP wp-sync-deploy
#
# COMMAND:
#
# `vendor/bin/wp-sync-deploy setup`
#

# The directory relative to the script
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Source functions for logging
source "$SCRIPT_DIR/lib/functions.sh"

CONFIG_EXAMPLE_FILE="$SCRIPT_DIR/wp-sync-deploy.config.example.php"
CONFIG_FILE="wp-sync-deploy.config.php"

TASKS_EXAMPLE_FILE="$SCRIPT_DIR/wp-sync-deploy.tasks.example.php"
TASKS_FILE="wp-sync-deploy.tasks.php"

# Ask before running the setup
log "🚀 Setup ${BLUE}wp-sync-deploy${NC} at this location?"
log "  ${GREEN}$(pwd)${NC}"

read -r -p "[y/n] " PROMPT_RESPONSE

# Exit if not confirmed
[[ "$PROMPT_RESPONSE" != "y" ]] && exit 1

log "🚀 Installing ${GREEN}wp-sync-deploy${NC} ... \n"

# Copy and rename the wp-sync-deploy.config.example.php to the working directory
if [ ! -e $CONFIG_FILE ]; then
    cp "$CONFIG_EXAMPLE_FILE" $CONFIG_FILE
    logSuccess "File ${GREEN}$CONFIG_FILE${NC} created! "
else
    logSuccess "File ${GREEN}$CONFIG_FILE${NC} already exists. "
fi

# Copy and rename the wp-sync-deploy.tasks.example.php to the working directory
if [ ! -e $TASKS_FILE ]; then
    cp "$TASKS_EXAMPLE_FILE" $TASKS_FILE
    logSuccess "File ${GREEN}$TASKS_FILE${NC} created!"
else
    logSuccess "File ${GREEN}$TASKS_FILE${NC} already exists. "
fi

log "\n🚀 Setup complete! Remember to adjust both files as required for your specific setup."