#!/usr/bin/env bash

# SETUP wp-sync-deploy
#
# COMMAND:
#
# `./wp-sync-deploy/setup.sh`
#

# The directory relative to the script
SCRIPT_DIR=$(realpath $(dirname $0))

# Source functions for logging
source "$SCRIPT_DIR/lib/functions.sh"

ENV_EXAMPLE_FILE="./wp-sync-deploy/.env.wp-sync-deploy.example"
ENV_FILE=".env.wp-sync-deploy"

TASKS_EXAMPLE_FILE="./wp-sync-deploy/wp-sync-deploy.tasks.example.php"
TASKS_FILE="wp-sync-deploy.tasks.php"

log "🚀 Installing ${GREEN}wp-sync-deploy${NC} ... \n"

# Copy and rename the wp-sync-deploy.example.env to the working directory
if [ ! -e $ENV_FILE ]; then
    cp $ENV_EXAMPLE_FILE $ENV_FILE
    logSuccess "File ${GREEN}$ENV_FILE${NC} created! "
else
    logSuccess "File ${GREEN}$ENV_FILE${NC} already exists. "
fi

# Copy and rename the wp-sync-deploy.tasks.example.php to the working directory
if [ ! -e $TASKS_FILE ]; then
    cp $TASKS_EXAMPLE_FILE $TASKS_FILE
    logSuccess "File ${GREEN}$TASKS_FILE${NC} created!"
else
    logSuccess "File ${GREEN}$TASKS_FILE${NC} already exists. "
fi

log "\n🚀 Setup complete! Remember to adjust both files as required for your specific setup."