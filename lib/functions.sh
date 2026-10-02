#!/usr/bin/env bash

# Font Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE="\033[0;36m"
NC='\033[0m' # No Color

# Font styles
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# Log a string and redirect to stderr to prevent function return pollution
# @see https://unix.stackexchange.com/a/331620/504158
function log() {
	printf "\n\r$1 " >&2
}

# Log an empty line
function logLine() {
	log ""
}

# Log an error message and exit with code 1
function logError() {
	log "🚨${BOLD}${RED} Error: ${NC}$1"
	exit 1
}

# Log a success message
function logSuccess() {
	log "✅${BOLD}${GREEN} Success: ${NC}$1"
}

# Dump something and exit
function dd() {
	log "$1"
	exit 1
}

# Load the env file for wp-sync-deploy
# - if --config was provided, use that file
# - first, look for .env.wp-sync-deploy file
# - second, fall back to the deprecated wp-sync-deploy.env file
function loadEnvFile() {
	# Use explicitly provided config file if set via --config
	if [[ -n "${WP_SYNC_DEPLOY_CONFIG_FILE:-}" ]]; then
		[ ! -e "$WP_SYNC_DEPLOY_CONFIG_FILE" ] && logError "Config file not found: ${RED}$WP_SYNC_DEPLOY_CONFIG_FILE${NC}"
		source "$WP_SYNC_DEPLOY_CONFIG_FILE"
		return
	fi

	# Find the closest wp-sync-deploy.env file
	ENV_FILE=$(findUp ".env.wp-sync-deploy" $SCRIPT_DIR)

	if [[ -z "$ENV_FILE" ]]; then
		ENV_FILE=$(findUp "wp-sync-deploy.env" $SCRIPT_DIR)
		[ -e "$ENV_FILE" ] && log "💡 Using ${RED}wp-sync-deploy.env${NC}. \n\r   Consider renaming the file to ${GREEN}.env.wp-sync-deploy${NC} instead\n\n\r"
	fi

	# Throw an error if no env file could be found
	[ -z "$ENV_FILE" ] && logError "No .env.wp-sync-deploy file found. Please run the ${BLUE}setup${NC} command and adjust your env file afterwards"

	# Load the environment variables
	source $ENV_FILE
}

# Normalize a path: trim trailing slashes
function normalizePath() {
  local path="${1:-}"
  trimTrailingSlashes "$path"
}

# Normalize a URL
# - trim whitespace
# - trim trailing slashes
function normalizeUrl() {
	local URL=$(trimTrailingSlashes $(trimWhitespace "$1"))
	echo $URL
}

# Trim all leading slashes from a string
function relativePath() {
  # make sure it's an empty string if none was provided
  local path="${1:-}"
	[[ "$path" == "/" || "$path" == "" ]] && echo "." && return
	(
		shopt -s extglob
		echo "${path##*(/)}"
	)
}

# Trim all trailing slashes from a string
function trimTrailingSlashes() {
	[ "$1" == "/" ] && echo "$1" && return
	(
		shopt -s extglob
		echo "${@%%+(/)}"
	)
}

# Trim whitespace from the beginning and end of a string
function trimWhitespace() {
	(
		shopt -s extglob
		# trim from the beginning
		local trimmed="${@##*( )}"
		# trim from the end and echo
		echo "${trimmed%%+( )}"
	)
}

# Find the closest file in parent directories
# @see https://unix.stackexchange.com/a/573499/504158
function findUp() {
	local file="$1"
	local dir="$2"

	test -e "$dir/$file" && echo "$dir/$file" && return 0
	[ "/" = "$dir" ] && return 0 # couldn't find a way to handle return code 1, so leaving it at zero for now

	findUp "$file" "$(dirname "$dir")"
}

# Check the git branch from the theme
function validateProductionBranch() {

	# Bail early if $GIT_DIR is not defined
	if [[ -z "${GIT_DIR+x}" ]]; then
		log "ℹ️  Skipping branch validation because ${BLUE}\$GIT_DIR${NC} is not defined"
		return
	fi

	# normalize the git directory
	ABSOLUTE_GIT_DIR=$(normalizePath "${LOCAL_ROOT_DIR}/${GIT_DIR}")

	# Get the branch from git directory
	cd "${ABSOLUTE_GIT_DIR}"
	local CURRENT_BRANCH=$(git branch --show)
	cd $LOCAL_WEB_ROOT

	# Validate the branch
	if [[ "${REMOTE_ENV}" == "production" && ! $CURRENT_BRANCH =~ $PRODUCTION_BRANCH ]]; then
		log "🚨 You are on the branch ${RED}${CURRENT_BRANCH}${NC}. Proceed deploy to ${BOLD}production${NORMAL}?"
		read -r -p "[y/n] " PROMPT_RESPONSE

		# Exit early if not confirmed
		if [[ "$PROMPT_RESPONSE" != "y" ]]; then
			log "❌ Deploy to $PRETTY_REMOTE_ENV canceled"
			exit
		fi
	else
		logSuccess "Branch ${BLUE}${CURRENT_BRANCH}${NC} allowed in ${BLUE}${REMOTE_ENV}${NC}"
	fi

}

# Check if there is a file `.allow-deployment` present at the remote root
function checkIsDeploymentAllowed() {
	local FILE_PATH="$REMOTE_ROOT_DIR/.allow-deployment"

	IS_ALLOWED=$($SSH_CONNECTION test -e "$FILE_PATH" && echo "yes" || echo "no")

	if [[ $IS_ALLOWED != "yes" ]]; then
		logError "Remote root ${RED}not allowed${NC} for deployment (missing file ${GREEN}.allow-deployment${NC})"
	else
		logSuccess "${BLUE}.allow-deployment${NC} detected on remote server"
	fi
}

# Check if the remote root is exists
function checkRemoteRootExists() {
	# Check if the remote root directory exists
	EXISTS=$($SSH_CONNECTION "[ -d \"$REMOTE_ROOT_DIR\" ] && echo \"yes\" || echo \"no\"")

	if [[ $EXISTS == "yes" ]]; then
		logSuccess "${BLUE}Remote root exists${NC}"
	else
		logError "${RED}Remote root does not exist: $REMOTE_ROOT_DIR${NC}"
	fi

}

# Check if the remote root exists and is empty
function checkRemoteRootExistsAndIsEmpty() {
	checkRemoteRootExists

	# Run the `find` command on the remote server to check for contents
	IS_EMPTY=$($SSH_CONNECTION "find \"$REMOTE_ROOT_DIR\" -mindepth 1 -print -quit | grep -q . && echo \"no\" || echo \"yes\"")

	if [[ $IS_EMPTY == "yes" ]]; then
		logSuccess "${BLUE}Remote root is empty${NC}"
	else
		logError "Remote root ${RED}is not empty${NC} (contains files or directories)"
	fi
}

# Create a hash from a string
function createHash() {
	echo "$1" | sha256sum | head -c 10
}

# Check if a URL is available
function validateUrlIsAvailable() {
	local URL="$1"

	if ! curl -s -f "$URL" >/dev/null; then
		logError "The URL '$URL' is not available."
	fi
}

# Check the PHP versions on the command line between two environments
function checkCommandLinePHPVersions() {
	local LOCAL_OUTPUT=$(php -v | head -n1 | awk '{print $2}')
	local LOCAL_VERSION=${LOCAL_OUTPUT:0:3}
	log "- Command line PHP version at $PRETTY_LOCAL_ENV server: ${BLUE}$LOCAL_VERSION${NC}"

	# The flag "-n" suppresses warnings
	local REMOTE_OUTPUT=$($SSH_CONNECTION "$REMOTE_PHP_BINARY -n -v | head -n1 | awk '{print \$2}'")
	local REMOTE_VERSION=${REMOTE_OUTPUT:0:3}
	log "- Command line PHP version at $PRETTY_REMOTE_ENV server: ${BLUE}$REMOTE_VERSION${NC}"

	if [[ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]]; then
		log "🚨 Command line PHP version mismatch detected. Proceed anyways?"
		read -r -p "[y/n] " PROMPT_RESPONSE

		# Exit early if not confirmed
		if [[ "$PROMPT_RESPONSE" != "y" ]]; then
			log "🚨 Deploy to $PRETTY_REMOTE_ENV canceled ..."
			exit
		fi
	else
		logSuccess "Command line PHP versions match between $PRETTY_LOCAL_ENV and $PRETTY_REMOTE_ENV"
	fi
}

# Fetch something with CURL.
# - follow redirects (--location)
# - optional http authentication, e.g. "username:password" as second argument
function fetch() {
	local URL="$1"
	local AUTH="${2:-}"

	if [ -z "$AUTH" ]; then
		curl --silent --fail --location --insecure "$URL" || logError "couldn't fetch URL: ${RED}$URL${NC}"
	else
		curl --silent --fail --location --insecure --user "$AUTH" "$URL" || logError "couldn't fetch URL: ${RED}$URL${NC}"
	fi
}

# Check the web-facing PHP versions between two environments
function checkWebFacingPHPVersions() {
	# Append a hash to the test file to make it harder to detect on the remote server
	local HASH=$(createHash $REMOTE_WEB_ROOT)
	FILE_NAME="___wp-sync-deploy-php-version-$HASH.php"

	# Create the test file on the local server
	echo "<?= phpversion();" >"$LOCAL_WEB_ROOT/$FILE_NAME"
	sleep 1
	# Get the output of the test file
	local LOCAL_OUTPUT=$(fetch "$LOCAL_URL/$FILE_NAME" "$LOCAL_HTTP_AUTH")
	# Cleanup the test file
	rm "$LOCAL_WEB_ROOT/$FILE_NAME"
	# substring from position 0-3
	local LOCAL_VERSION=${LOCAL_OUTPUT:0:3}
	# validate if the version looks legit
	[[ ! $LOCAL_VERSION =~ ^[0-9]\. ]] && logError "Invalid local web-facing PHP version number: $LOCAL_VERSION"
	# Log the detected PHP version
	log "- Web-facing PHP version at $PRETTY_LOCAL_HOST: ${BLUE}$LOCAL_VERSION${NC}"

	# Create the test file on the remote server
	$SSH_CONNECTION "cd $REMOTE_WEB_ROOT; echo '<?= phpversion();' > ./$FILE_NAME"

	# Get the output of the test file
	local REMOTE_OUTPUT=$(fetch "$REMOTE_URL/$FILE_NAME" "$REMOTE_HTTP_AUTH")

	# Cleanup the test file
	$SSH_CONNECTION "cd $REMOTE_WEB_ROOT; rm ./$FILE_NAME"
	# substring from position 0-3
	local REMOTE_VERSION=${REMOTE_OUTPUT:0:3}
	# validate if the version looks legit
	[[ ! $REMOTE_VERSION =~ ^[0-9]\. ]] && logError "Invalid remote web-facing PHP version number: $REMOTE_VERSION"
	# Log the detected PHP version
	log "- Web-facing PHP version at $PRETTY_REMOTE_HOST: ${BLUE}$REMOTE_VERSION${NC}"

	# Error out if the two PHP versions aren't a match
	if [[ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]]; then
		logError "Web-Facing PHP versions mismatch. Aborting."
	else
		logSuccess "Web-facing PHP versions match between $PRETTY_LOCAL_ENV and $PRETTY_REMOTE_ENV"
	fi
}

# Check if a file exists on a remote server
function checkRemoteFile() {
	ssh -p $REMOTE_SSH_PORT $REMOTE_SSH "[ -e \"$1\" ] && echo 1 || echo 0"
}

# Validate that the required directories exist locally and remotely
function checkDeployPaths() {
	for DEPLOY_DIR in $DEPLOY_PATHS; do
		local LOCAL_PATH="${LOCAL_ROOT_DIR}/${DEPLOY_DIR}"
		local REMOTE_PATH="${REMOTE_ROOT_DIR}/${DEPLOY_DIR}"

		# check on local machine
		if [ ! -e "$LOCAL_PATH" ]; then
			logError "The directory ${RED}$LOCAL_PATH${NC} does not exist locally"
		fi
		# check on remote machine
		if [[ $(checkRemoteFile "$REMOTE_PATH") != 1 ]]; then
			logError "The directory ${RED}$REMOTE_PATH${RED} does not exist on the remote server"
		fi
		logSuccess "Folder exists at ${PRETTY_REMOTE_ENV}: ${BLUE}$DEPLOY_DIR${NC}"
	done
}

# Get the remote wp-cli.phar file name
function getRemoteWPCLIFilename() {
	local HASH=$(createHash $REMOTE_WEB_ROOT)
	echo "wp-cli-$HASH.phar"
}

# Install WP-CLI on the remote server
# This makes it possible to easily run wp-cli with a custom command line PHP version

function installRemoteWpCli() {
	# Get the hashed filename of the wp-cli.phar
	local WP_CLI_PHAR=$(getRemoteWPCLIFilename)

	# Don't install twice, but keep an existing install up to date
	if [ $(checkRemoteFile "$REMOTE_WEB_ROOT/$WP_CLI_PHAR") == 1 ]; then
		updateRemoteWpCli
		logSuccess "WP-CLI available on the remote server."
		return
	fi

	log "🚀 Installing WP-CLI on the remote server ..."

	RESULT=$($SSH_CONNECTION "cd $REMOTE_WEB_ROOT && curl -s -o $WP_CLI_PHAR https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && echo success")

	[ ! "$RESULT" == 'success' ] && logError "Failed to install WP-CLI on the server"

	logSuccess "WP-CLI installed on the remote server\n"
}

# Update an existing WP-CLI on the remote server, once per script run.
# A stale phar can emit deprecation notices under newer PHP versions.
# A marker file is used instead of a variable, as wpRemote often runs in a
# subshell when its output is piped. $$ stays the same in those subshells.
WP_CLI_UPDATE_MARKER="${TMPDIR:-/tmp}/wp-sync-deploy-wp-cli-updated-$$"
function updateRemoteWpCli() {
	[ -e "$WP_CLI_UPDATE_MARKER" ] && return
	touch "$WP_CLI_UPDATE_MARKER"

	local WP_CLI_PHAR=$(getRemoteWPCLIFilename)
	local RESULT

	if ! RESULT=$($SSH_CONNECTION "cd $REMOTE_WEB_ROOT && $REMOTE_PHP_BINARY $WP_CLI_PHAR cli update --yes 2>&1"); then
		log "⚠️  Failed to update WP-CLI on the remote server:\n\r$RESULT"
		return
	fi

	log "$RESULT"
}

# Run wp cli on a remote server, forwarding all arguments
function wpRemote() {
	local ARGS="$@"

	# Install WP-CLI on remote server
	installRemoteWpCli

	# Log an empty line
	logLine

	# Get the hashed file name of the wp-cli.phar
	local WP_CLI_PHAR=$(getRemoteWPCLIFilename)

	# Construct the remote command
	local SSH_COMMAND="ssh -p $REMOTE_SSH_PORT $REMOTE_SSH 'cd $REMOTE_WEB_ROOT && $REMOTE_PHP_BINARY $WP_CLI_PHAR $ARGS'"

	# @see ChatGPT
	eval $SSH_COMMAND
}

# Runs the task file on the remote server
function runRemoteTasks() {
	[ ! -e "$TASKS_FILE" ] && return

	local TASK="$1"

	log "Running ${BLUE}wp eval-file wp-sync-deploy.tasks.php $TASK${NC} on $PRETTY_REMOTE_ENV server ... \n"

	# Upload the file to the remote web root
	rsync -e "ssh -p $REMOTE_SSH_PORT" -q "$TASKS_FILE" "$REMOTE_SSH:$REMOTE_WEB_ROOT/"

	# Execute the file on the remote server, passing in the current $TASK ("deploy" or "sync")
	wpRemote eval-file "$REMOTE_WEB_ROOT/wp-sync-deploy.tasks.php" "$TASK"
}

# Pull the remote database into the local database
function pullDatabase() {
	# Confirmation dialog
	log "🔄 Would you really like to 💥 ${RED}reset the local database${NC} ($PRETTY_LOCAL_HOST)"
	log "and sync from ${BOLD}$REMOTE_ENV${NORMAL} ($PRETTY_REMOTE_HOST)?"
	read -r -p "[y/n] " PROMPT_RESPONSE

	# Return early if not confirmed
	[[ "$PROMPT_RESPONSE" != "y" ]] && exit 1

	# Activate maintenance mode
	wp maintenance-mode activate

	# Import the remote database into the local database
	# Removes lines containing '999999' followed by 'enable the sandbox'
	# @see https://mariadb.org/mariadb-dump-file-compatibility-change/
	wpRemote db export --default-character-set=utf8mb4 - | sed '/999999.*enable the sandbox/d' | wp db import -

	# Replace the remote URL with the local URL
	wp search-replace "//$REMOTE_HOST" "//$LOCAL_HOST" --all-tables-with-prefix

	# Deactivate maintenance mode
	wp maintenance-mode deactivate

	# Run tasks on the local server
	wp eval-file "$TASKS_FILE" sync

	# Delete local transients
	wp transient delete --all

	logLine && logSuccess "Database imported from ${GREEN}$REMOTE_URL${NC} to ${GREEN}$LOCAL_URL${NC}"
}

# Backup a remote database and store it locally
function backupDatabase() {
	local NAME="$REMOTE_HOST-$(date +"%Y-%m-%d_%H-%M-%S").sql"
	wpRemote db export --default-character-set=utf8mb4 - | sed '/999999.*enable the sandbox/d' >"$NAME"
	logLine && logSuccess "Database backup saved to ${GREEN}$NAME${NC}"
}

# Push the local database to the remote environment
function pushDatabase() {

	[ "$REMOTE_ENV" == "production" ] && logError "Syncing to the production database is not allowed for security reasons"

	# Confirmation dialog
	log "🚨 Would you really like to 💥 ${RED}reset the $REMOTE_ENV database${NC} ($PRETTY_REMOTE_HOST)"
	log "and ${RED}push from local${NC}?"
	read -r -p "Type '$REMOTE_HOST' to continue ... " PROMPT_RESPONSE

	# Return early if not confirmed
	[[ "$PROMPT_RESPONSE" != "$REMOTE_HOST" ]] && logError "Permission denied, aborting ..."

	# Activate maintenance mode on the remote server
	wpRemote maintenance-mode activate &&

		# Import the local database into the remote database
		wp db export --default-character-set=utf8mb4 - | wpRemote db import - &&

		# Replace the local URL with the remote URL
		wpRemote search-replace "//$LOCAL_HOST" "//$REMOTE_HOST" --all-tables-with-prefix

	# Deactivate maintenance mode on the remote server
	wpRemote maintenance-mode deactivate

	# Run tasks on the remote server
	runRemoteTasks sync

	# Delete remote transients
	wpRemote transient delete --all

	logLine && logSuccess "Pushed the database from ${GREEN}$LOCAL_URL${NC} to ${GREEN}$REMOTE_URL${NC}"
}

# Resolve the rsync binary to use.
#
# Recent macOS releases ship openrsync as /usr/bin/rsync instead of GNU rsync,
# and its --delete semantics are unsafe here — see requireGnuRsync() for details.
#
# Honours $RSYNC_BIN if set, otherwise prefers a Homebrew GNU rsync.
function resolveRsyncBin() {
	local bin="${RSYNC_BIN:-}"

	if [[ -z "$bin" ]]; then
		for candidate in /opt/homebrew/bin/rsync /usr/local/bin/rsync rsync; do
			if command -v "$candidate" >/dev/null 2>&1; then
				bin=$(command -v "$candidate")
				break
			fi
		done
	fi

	[[ -z "$bin" ]] && logError "No rsync binary found. Please install rsync."
	command -v "$bin" >/dev/null 2>&1 || logError "rsync binary not found: ${RED}$bin${NC}"

	echo "$bin"
}

# Abort if the resolved rsync is openrsync.
#
# openrsync's --delete is inverted relative to GNU rsync and cannot be made
# safe with filter rules. Verified against openrsync (protocol 29, reporting
# itself as "rsync version 2.6.9 compatible") on macOS 27:
#
#   - it DOES delete inside the implied parent directories of --relative paths
#     (so $PUBLIC_DIR/wp-config.php, $PUBLIC_DIR/index.php, $PUBLIC_DIR/.htaccess
#     and $WP_CONTENT_DIR/uploads all get wiped)
#   - it does NOT delete stale files inside the directories actually being
#     transferred (so removed plugins/themes linger forever)
#
# Both behaviours persist regardless of any `P` protect rules, so there is no
# safe invocation. Refuse to run instead.
function requireGnuRsync() {
	local bin="$1"

	# Avoid a pipeline here: `set -o pipefail` would surface the SIGPIPE from
	# `--version` once grep/head exit early and mask the match.
	local version
	version=$("$bin" --version 2>&1 || true)
	[[ "$version" == *openrsync* || "$version" == *OpenRSYNC* ]] || return 0

	log "🚨${BOLD}${RED} Error: openrsync detected${NC} at ${BLUE}$bin${NC}"
	log ""
	log "   Recent macOS releases ship openrsync as /usr/bin/rsync instead of GNU"
	log "   rsync. Its ${BOLD}--delete${NORMAL} is unsafe for deployments: it deletes undeployed"
	log "   files such as ${BLUE}$PUBLIC_DIR/wp-config.php${NC} and ${BLUE}$PUBLIC_DIR/index.php${NC},"
	log "   while leaving stale plugins and themes in place."
	log ""
	log "   Note openrsync reports ${BLUE}rsync version 2.6.9 compatible${NC}, so a version"
	log "   check won't catch it — this guard greps for ${BLUE}openrsync${NC} instead."
	log ""
	log "   Install GNU rsync:  ${BLUE}brew install rsync${NC}"
	log "   Or point wp-sync-deploy at one:  ${BLUE}export RSYNC_BIN=/path/to/gnu/rsync${NC}"
	logLine
	exit 1
}

# Check if a path equals or is nested inside one of the given deploy paths
function isInsideDeployPaths() {
	local path="$1" deployPath
	for deployPath in $2; do
		[[ "$path" == "$deployPath" || "$path" == "$deployPath/"* ]] && return 0
	done
	return 1
}

# Build `protect` filter rules for the implied parent directories of the given
# deploy paths, so that files we never deploy can't be deleted by --delete.
#
# For a deploy path of `public/content/plugins` this emits:
#   R /public/content/plugins
#   R /public/content
#   R /public
#   P /public/content/*
#   P /public/*
#
# `P /dir/*` protects the direct children of /dir only — files *inside* the
# deployed directories themselves are still deleted when they go stale.
# The leading `R` rules exempt the deployed paths and their parents (first match
# wins), as older receivers (e.g. rsync 3.1.3) abort on file-list names matching a `P`.
function buildProtectFilters() {
	local paths="$1"
	local -a risks=() protects=()
	local path parent rule seen=""

	for path in $paths; do
		parent="$path"
		while [[ "$parent" != "." && "$parent" != "/" && "$parent" != "" ]]; do
			rule="R /$parent"
			if [[ "$seen" != *"[$rule]"* ]]; then
				seen="$seen[$rule]"
				risks+=("--filter=$rule")
			fi
			parent=$(dirname "$parent")
		done

		parent=$(dirname "$path")
		while [[ "$parent" != "." && "$parent" != "/" && "$parent" != "" ]]; do
			rule="P /$parent/*"
			# Skip parents that are deployed themselves, so --delete stays effective there
			if ! isInsideDeployPaths "$parent" "$paths" && [[ "$seen" != *"[$rule]"* ]]; then
				seen="$seen[$rule]"
				protects+=("--filter=$rule")
			fi
			parent=$(dirname "$parent")
		done
	done

	printf '%s\n' "${risks[@]}" "${protects[@]}"
}
