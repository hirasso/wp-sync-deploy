#!/usr/bin/env bash

# Log a string
function log() {
    printf "\r\n$1 ";
}

# Log an empty line
function logLine() {
    log ""
}

# Log an error message and exit with code 1
function logError() {
    log "🚨${BOLD}${RED} Error: ${NC}$1";
    exit 1;
}

# Log a success message
function logSuccess() {
    log "✅${BOLD}${GREEN} Success: ${NC}$1";
}

# Find the closest file in parent directories
# @see https://unix.stackexchange.com/a/573499/504158
function findUp() {
    local file="$1"
    local dir="$2"

    test -e "$dir/$file" && echo "$dir/$file" && return 0
    [ '/' = "$dir" ] && return 0 # couldn't find a way to handle return code 1, so leaving it at zero for now

    findUp "$file" "$(dirname "$dir")"
}

# Check the git branch from the theme
function checkProductionBranch() {
    # Bail early if not deploying to production
    [[ $REMOTE_ENV != "production" ]] && return;

    # Get the branch from the theme
    cd "$LOCAL_WEB_ROOT/content/themes/$WP_THEME";
    BRANCH=$(git branch --show);
    cd $LOCAL_WEB_ROOT;

    # Check it
    if [[ ! $BRANCH =~ $MAIN_BRANCH ]]; then
        logError "Deploying to production is only allowed from ${NC}\$MAIN_BRANCH${RED} ($MAIN_BRANCH)"
    else
        logSuccess "Branch $BRANCH allowed in production"
    fi
}

# Check if there is a file `.allow-deployment` present at the remote root
function checkIsRemoteAllowed() {
    local FILE_PATH="$REMOTE_WEB_ROOT/.allow-deployment"
    IS_ALLOWED=$(ssh "$SSH_USER@$SSH_HOST" test -e "$FILE_PATH" && echo "yes" || echo "no")

    if [[ $IS_ALLOWED != "yes" ]]; then
        logError "Remote root ${RED}not allowed${NC} for deployment (missing file ${GREEN}.allow-deployment${NC})"
    else
        logSuccess ".allow-deployment detected on remote server"
    fi;
}

# Create a hash from a string
function createHash() {
    echo "$1" | sha256sum | head -c 10
}

# Check the PHP version between two environments
function checkPHPVersions() {
    local FILE_NAME="___wp-sync-deploy-php-version.php"

    # Create the test file on the local server
    echo "<?= phpversion();" > "$LOCAL_WEB_ROOT/$FILE_NAME"
    # Get the output of the test file
    local LOCAL_OUTPUT=$(curl -s "$LOCAL_PROTOCOL://$LOCAL_URL/$FILE_NAME")
    # Cleanup the test file
    rm "$LOCAL_WEB_ROOT/$FILE_NAME"
    # substring from position 0-3
    local LOCAL_VERSION=${LOCAL_OUTPUT:0:3}
    # validate if the version looks legit
    [[ ! $LOCAL_VERSION =~ ^[0-9]\. ]] && logError "Invalid PHP version number: $LOCAL_VERSION"
    # Log the detected PHP version
    log "- PHP version ${GREEN}$LOCAL_VERSION${NC} detected at ${BOLD}$LOCAL_URL${NC}"


    # Append a hash to the remote test file to make it harder to detect
    local HASH=$(createHash $REMOTE_WEB_ROOT)
    FILE_NAME="___wp-sync-deploy-php-version-$HASH.php"
    # Create the test file on the remote server
    ssh "$SSH_USER@$SSH_HOST" "cd $REMOTE_WEB_ROOT; echo '<?= phpversion();' > ./$FILE_NAME"
    # Get the output of the test file
    local REMOTE_OUTPUT=$(curl -s "$REMOTE_PROTOCOL://$REMOTE_URL/$FILE_NAME")
    # Cleanup the test file
    ssh "$SSH_USER@$SSH_HOST" "cd $REMOTE_WEB_ROOT; rm ./$FILE_NAME"
    # substring from position 0-3
    local REMOTE_VERSION=${REMOTE_OUTPUT:0:3}
    # validate if the version looks legit
    [[ ! $REMOTE_VERSION =~ ^[0-9]\. ]] && logError "Invalid PHP version number: $REMOTE_VERSION"
    # Log the detected PHP version
    log "- PHP version ${GREEN}$REMOTE_VERSION${NC} detected at ${BOLD}$REMOTE_URL${NC}"

    # Error out if the two PHP versions aren't a match
    if [[ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]]; then
        logError "PHP version mismatch, aborting"
    else
        logSuccess "PHP versions match between environments"
    fi
}

# Checks if a file exists on a remote server
function checkRemoteFile() {
    ssh $SSH_USER@$SSH_HOST "[ -e \"$REMOTE_WEB_ROOT/$1\" ] && echo 1";
}

# Validate that the required directories exist locally and remotely
function checkDirectories() {
    for DEPLOY_DIR in $DEPLOY_DIRS; do
        # check on remote machine
        if [[ $(checkRemoteFile $DEPLOY_DIR) != 1 ]]; then
            logError "The directory ${GREEN}$deploy_dir${RED} does not exist on the remote server"
        fi
        # check on local machine
        if [ ! -d "$LOCAL_WEB_ROOT/$DEPLOY_DIR" ]; then
            logError "The directory ${RED}$LOCAL_WEB_ROOT/$DEPLOY_DIR${NC} does not exist locally"
        fi
    done

    logSuccess "All directories exist in both environments"
}

# Run wp cli on a remote server, forwarding all arguments
function wpRemote() {
    ARGS="$@"

    log "Would you like to run ${BLUE}wp $ARGS${NC} on the ${BOLD}$REMOTE_ENV${NORMAL} server?"
    read -r -p "[y/N] " PROMPT_RESPONSE

    # Exit if not confirmed
    [[ ! "$PROMPT_RESPONSE" =~ ^([yY][eE][sS]|[yY])$ ]] && return;

    log "proceeding ..."

    local PREFLIGHT=$(wp --ssh="$SSH_USER@$SSH_HOST$REMOTE_WEB_ROOT" option get home 2>&1)
    local FIRST_LINE=$(echo "$PREFLIGHT" | head -n 1)
    # Check for "error" or "command not found" in the response
    if [[ $PREFLIGHT == *"Error"* || $PREFLIGHT == *"command not found"* ]]; then
        log "🚨 Unable to run WP-CLI on ${BOLD}$REMOTE_ENV${NORMAL}: \n\n $FIRST_LINE"
        return;
    fi

    # preflight passed, exectute the command
    wp --ssh="$SSH_USER@$SSH_HOST$REMOTE_WEB_ROOT" $ARGS
}