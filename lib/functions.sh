#!/usr/bin/env bash

# Log a string
function log() {
    printf "\r\n$1";
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
    cd "$ROOT_DIR/content/themes/$WP_THEME";
    BRANCH=$(git branch --show);
    cd $ROOT_DIR;

    # Check it
    if [[ ! $BRANCH =~ $MAIN_BRANCH ]]; then
        logError "Deploying to production is only allowed from ${NC}\$MAIN_BRANCH${RED} ($MAIN_BRANCH)"
    else
        logSuccess "Branch $BRANCH allowed in production"
    fi
}

# Check if there is a file `.allow-deployment` present at the remote root
function checkIsRemoteAllowed() {
    ALLOWED=$(eval "ssh $SSH_USER@$SSH_HOST 'cd $SSH_PATH; [ -f \"$SSH_PATH/.allow-deployment\" ] && echo 1'")

    if [[ $ALLOWED != 1 ]]; then
        logError "Remote root ${RED}not allowed${NC} for deployment (missing file .allow-deployment):

        $SSH_USER@$SSH_HOST:$SSH_PATH"
    else
        logSuccess ".allow-deployment detected on remote server"
    fi;
}

# Check the PHP version between two environments
function checkPHPVersions() {
    # The file name for the PHP check. Appends a hash to make the file hard to detect.
    # The file will be automatically deleted after this script finishes
    local HASH=$(echo $(date +%s%N) | sha256sum | head -c 10)
    local FILE_NAME="___wp-sync-deploy-php-version-$HASH.php"

    # Get the local PHP Version
    echo "<?= phpversion();" > "./$FILE_NAME"
    local LOCAL_VERSION=$(curl -s "$LOCAL_PROTOCOL://$LOCAL_URL/$FILE_NAME")
    # substring from position 0-3
    local LOCAL_VERSION=${LOCAL_VERSION:0:3}
    rm "./$FILE_NAME"
    log "- PHP version ${GREEN}$LOCAL_VERSION${NC} detected at ${BOLD}$LOCAL_URL${NC}"

    # Do the same on the remote server
    ssh "$SSH_USER@$SSH_HOST" "cd $SSH_PATH; echo '<?= phpversion();' > ./$FILE_NAME"

    # The remote file URL
    local REMOTE_FILE_URL="$REMOTE_PROTOCOL://$REMOTE_URL/$FILE_NAME"

    # Check if the remote file actually exists
    local REMOTE_FILE_RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" $REMOTE_FILE_URL)
    [[ $REMOTE_FILE_RESPONSE_CODE != 200 ]] && logError "Something went wrong while trying to detect the remote PHP version. Please try again."

    # Get the version from the remote file
    local REMOTE_VERSION=$(curl -s $REMOTE_FILE_URL)
    # substring from position 0-3
    local REMOTE_VERSION=${REMOTE_VERSION:0:3}

    log "- PHP version ${GREEN}$REMOTE_VERSION${NC} detected at ${BOLD}$REMOTE_URL${NC}"

    # Remove the file to prevent security issues
    ssh "$SSH_USER@$SSH_HOST" "cd $SSH_PATH; rm ./$FILE_NAME"

    # Error out if the two PHP versions aren't a match
    if [[ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]]; then
        logError "PHP version mismatch, aborting"
    else
        logSuccess "PHP versions match between environments"
    fi
}

# Checks if a file exists on a remote server
function checkRemoteFile() {
    ssh $SSH_USER@$SSH_HOST "[ -e \"$SSH_PATH/$1\" ] && echo 1";
}

# Validate that the required directories exist locally and remotely
function checkDirectories() {
    for deploy_dir in $DEPLOY_DIRS; do
        # check on remote machine
        if [[ $(checkRemoteFile $deploy_dir) != 1 ]]; then
            logError "The directory ${GREEN}$deploy_dir${RED} does not exist on the remote server"
        fi
        # check on local machine
        if [ ! -d "$ROOT_DIR/$deploy_dir" ]; then
            logError "The directory ${GREEN}$ROOT_DIR/$deploy_dir${RED} does not exist locally"
        fi
    done

    logSuccess "All directories exist in both environments"
}