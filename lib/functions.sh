#!/usr/bin/env bash

# Font colors and styles, only in a terminal (log writes to stderr) and without NO_COLOR
RED='' GREEN='' BLUE='' NC='' BOLD='' NORMAL=''
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	BLUE="\033[0;36m"
	NC='\033[0m' # No Color
	BOLD=$(tput bold)
	NORMAL=$(tput sgr0)
fi

# Log a string and redirect to stderr to prevent function return pollution
# @see https://unix.stackexchange.com/a/331620/504158
function log() {
	printf "\n\r$1" >&2
}

# Log an empty line
function logLine() {
	log ""
}

# Log an error message and exit with code 1
function logError() {
	log "🚨 $1"
	exit 1
}

# Log a success message
function logSuccess() {
	log "${GREEN}✔${NC} $1"
}

# Log a warning message
function logWarning() {
	log "⚠️  $1"
}

# Dump something and exit
function dd() {
	log "$1"
	exit 1
}

# Load the wp-sync-deploy.config.php file
# - if --config was provided, use that file
# - otherwise, find the closest wp-sync-deploy.config.php
function loadConfigFile() {
	# Hard cut: the .env config was removed in 4.0.0
	local LEGACY_FILE
	for LEGACY_FILE in ".env.wp-sync-deploy" "wp-sync-deploy.env"; do
		[ -n "$(findUp "$LEGACY_FILE" $SCRIPT_DIR)" ] && logError "${RED}$LEGACY_FILE${NC} is not supported anymore. Run ${GREEN}vendor/bin/wp-sync-deploy config init${NC} to migrate it to ${GREEN}wp-sync-deploy.config.php${NC}.\n   @see https://github.com/hirasso/wp-sync-deploy#upgrading-from-3x"
	done

	CONFIG_FILE="${WP_SYNC_DEPLOY_CONFIG_FILE:-}"
	if [[ -n "$CONFIG_FILE" ]]; then
		[ ! -e "$CONFIG_FILE" ] && logError "Config file not found: ${RED}$CONFIG_FILE${NC}"
	else
		CONFIG_FILE=$(findUp "wp-sync-deploy.config.php" $SCRIPT_DIR)
		[ -z "$CONFIG_FILE" ] && logError "No wp-sync-deploy.config.php file found. Please run the ${BLUE}setup${NC} command and adjust your config file afterwards"
	fi

	local VARS
	VARS=$(php -d display_errors=stderr "$SCRIPT_DIR/lib/config.php" "$CONFIG_FILE") || logError "Invalid config file ${RED}$CONFIG_FILE${NC}"
	eval "$VARS"
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

# Ask for confirmation to continue the deploy.
# On dry runs, remember the reason for the summary instead (see logDryRunSummary)
function confirmDeploy() {
	local REASON="$1"
	if [[ "$DEPLOY_MODE" == "dry" ]]; then
		DRY_RUN_CONFIRMATIONS="${DRY_RUN_CONFIRMATIONS:-}\n\r   - $REASON"
		return 0
	fi

	read -r -p " Deploy anyway? [y/n] " PROMPT_RESPONSE
	if [[ "$PROMPT_RESPONSE" != "y" ]]; then
		log "❌ Deploy to $PRETTY_REMOTE_ENV canceled"
		exit 1
	fi
}

# List everything a live deploy will ask for confirmation
function logDryRunSummary() {
	[[ -z "${DRY_RUN_CONFIRMATIONS:-}" ]] && return 0
	logWarning "${BOLD}${RED}A live deploy will ask for confirmation:${NC}${NORMAL}$DRY_RUN_CONFIRMATIONS"
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
		logWarning "You are on the branch ${RED}${CURRENT_BRANCH}${NC}"
		confirmDeploy "You are on the branch ${RED}${CURRENT_BRANCH}${NC}"
	else
		logSuccess "Branch ${BLUE}${CURRENT_BRANCH}${NC} allowed in ${BLUE}${REMOTE_ENV}${NC}"
	fi

}

# Ask for confirmation if the git repo has uncommitted changes or unpushed commits
function checkGitState() {
	[[ -z "${GIT_DIR+x}" || "${REMOTE_ENV}" != "production" ]] && return

	local DIR=$(normalizePath "${LOCAL_ROOT_DIR}/${GIT_DIR}")
	local CHANGES=$(git -C "$DIR" status --porcelain | wc -l | tr -d ' ')
	local PROBLEMS=""

	[[ "$CHANGES" != "0" ]] && PROBLEMS="$PROBLEMS\n\r   - ${RED}$CHANGES${NC} uncommitted change(s)"

	if git -C "$DIR" rev-parse --verify --quiet "@{upstream}" >/dev/null; then
		local UNPUSHED=$(git -C "$DIR" rev-list --count "@{upstream}..HEAD")
		[[ "$UNPUSHED" != "0" ]] && PROBLEMS="$PROBLEMS\n\r   - ${RED}$UNPUSHED${NC} unpushed commit(s)"
	else
		PROBLEMS="$PROBLEMS\n\r   - the branch has ${RED}not been pushed${NC} yet"
	fi

	if [[ -z "$PROBLEMS" ]]; then
		logSuccess "Git repo is clean and pushed"
		return
	fi

	logWarning "${BOLD}${RED}Your git repo differs from the remote repo${NC}${NORMAL}$PROBLEMS"
	confirmDeploy "Your git repo differs from the remote repo"
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

# Warn if the installed version is below the minimum version on main
function checkMinimumSelfVersion() {
	local installed_json="$SCRIPT_DIR/../../composer/installed.json"
	[ -f "$installed_json" ] || return 0

	local installed
	installed=$(grep -A1 '"name": "hirasso/wp-sync-deploy"' "$installed_json" | sed -n 's/.*"version": "\(.*\)".*/\1/p')
	[[ "$installed" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 0

	local minimum
	minimum=$(curl -fsSL --max-time 2 "https://raw.githubusercontent.com/hirasso/wp-sync-deploy/main/.minimum-version") || return 0
	minimum=$(trimWhitespace "$minimum")

	[ "$(printf '%s\n' "$minimum" "$installed" | sort -V | head -1)" = "$minimum" ] && return 0

	logWarning "${BOLD}${RED}Important update:${NC} wp-sync-deploy $installed is outdated, please update to $minimum or later"
	log "   ${BLUE}composer update hirasso/wp-sync-deploy${NC}"
	log "   https://github.com/hirasso/wp-sync-deploy/releases"
	read -r -p " Continue anyway? [y/n] " PROMPT_RESPONSE
	[[ "$PROMPT_RESPONSE" != "y" ]] && exit 1
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
	log "   - Command line PHP version at $PRETTY_LOCAL_ENV server: ${BLUE}$LOCAL_VERSION${NC}"

	# The flag "-n" suppresses warnings
	local REMOTE_OUTPUT=$($SSH_CONNECTION "$REMOTE_PHP_BINARY -n -v | head -n1 | awk '{print \$2}'")
	local REMOTE_VERSION=${REMOTE_OUTPUT:0:3}
	log "   - Command line PHP version at $PRETTY_REMOTE_ENV server: ${BLUE}$REMOTE_VERSION${NC}"

	if [[ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]]; then
		logWarning "Command line PHP version mismatch detected"
		confirmDeploy "Command line PHP version mismatch"
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
	log "   - Web-facing PHP version at $PRETTY_LOCAL_HOST: ${BLUE}$LOCAL_VERSION${NC}"

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
	log "   - Web-facing PHP version at $PRETTY_REMOTE_HOST: ${BLUE}$REMOTE_VERSION${NC}"

	# Error out if the two PHP versions aren't a match
	if [[ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]]; then
		logError "Web-Facing PHP versions mismatch. Aborting."
	else
		logSuccess "Web-facing PHP versions match between $PRETTY_LOCAL_ENV and $PRETTY_REMOTE_ENV"
	fi
}

# Check if a file exists on a remote server
function checkRemoteFile() {
	$SSH_CONNECTION "[ -e \"$1\" ] && echo 1 || echo 0"
}

# Validate that the required directories exist locally and remotely
function checkDeployPaths() {
	# Missing essentials indicate a wrong remote root. Other paths will be created by rsync
	local REQUIRED_PATHS=" $WP_CORE_DIR $WP_CONTENT_DIR/plugins $WP_CONTENT_DIR/themes "

	for DEPLOY_DIR in $DEPLOY_PATHS; do
		local LOCAL_PATH="${LOCAL_ROOT_DIR}/${DEPLOY_DIR}"
		local REMOTE_PATH="${REMOTE_ROOT_DIR}/${DEPLOY_DIR}"

		# check on local machine
		if [ ! -e "$LOCAL_PATH" ]; then
			logError "The directory ${RED}$LOCAL_PATH${NC} does not exist locally"
		fi
		# check on remote machine
		if [[ $(checkRemoteFile "$REMOTE_PATH") == 1 ]]; then
			logSuccess "Folder exists at ${PRETTY_REMOTE_ENV}: ${BLUE}$DEPLOY_DIR${NC}"
		elif [[ "$REQUIRED_PATHS" == *" $DEPLOY_DIR "* ]]; then
			logError "The directory ${RED}$REMOTE_PATH${NC} does not exist on the remote server"
		else
			log "ℹ️  Folder will be created at ${PRETTY_REMOTE_ENV}: ${BLUE}$DEPLOY_DIR${NC}"
		fi
	done
}

# WP-CLI and the tasks file are uploaded to the remote home dir, outside of the web root.
# Running our own WP-CLI makes it possible to use a custom command line PHP version
WP_CLI_LOCAL_PHAR="${XDG_CACHE_HOME:-$HOME/.cache}/wp-sync-deploy/wp-cli.phar"
REMOTE_FILES_DIR=".wp-sync-deploy"

# Download WP-CLI to the local cache, or update it if older than a week.
# A stale phar can emit deprecation notices under newer PHP versions.
function cacheWpCli() {
	[ -n "$(find "$WP_CLI_LOCAL_PHAR" -mtime -7 2>/dev/null)" ] && return

	local TMP_PHAR="$WP_CLI_LOCAL_PHAR.tmp"
	mkdir -p "$(dirname "$WP_CLI_LOCAL_PHAR")"

	if curl -fsSL -o "$TMP_PHAR" https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar &&
		php "$TMP_PHAR" --version >/dev/null 2>&1; then
		mv "$TMP_PHAR" "$WP_CLI_LOCAL_PHAR"
		return
	fi

	rm -f "$TMP_PHAR"
	[ ! -e "$WP_CLI_LOCAL_PHAR" ] && logError "Failed to download WP-CLI to ${BLUE}$WP_CLI_LOCAL_PHAR${NC}"
	logWarning "Failed to update WP-CLI at ${BLUE}$WP_CLI_LOCAL_PHAR${NC}, using the existing one"
}

# Upload WP-CLI to the remote server, once per script run.
# A marker file is used instead of a variable, as wpRemote often runs in a
# subshell when its output is piped. $$ stays the same in those subshells.
WP_CLI_MARKER="${TMPDIR:-/tmp}/wp-sync-deploy-wp-cli-$$"
function installRemoteWpCli() {
	[ -e "$WP_CLI_MARKER" ] && return
	touch "$WP_CLI_MARKER"

	cacheWpCli

	local RESULT
	# rsync only transfers changed files. </dev/null keeps rsync and ssh from reading wpRemote's piped stdin
	RESULT=$("$RSYNC_BIN" -t -e "$SSH_COMMAND" --rsync-path="mkdir -p $REMOTE_FILES_DIR && rsync" \
		"$WP_CLI_LOCAL_PHAR" "$SCRIPT_DIR/lib/wp-cli-setup.php" "$REMOTE_SSH:$REMOTE_FILES_DIR/" </dev/null 2>&1) ||
		logError "Failed to upload WP-CLI to ${BLUE}~/$REMOTE_FILES_DIR/wp-cli.phar${NC} on the remote server. Is the home directory writable?\n\r$RESULT"

	# Legacy: remove the hashed phar and the tasks file from the web root, uploaded by wp-sync-deploy < 4.1
	$SSH_CONNECTION "rm -f '$REMOTE_WEB_ROOT/wp-cli-$(createHash $REMOTE_WEB_ROOT).phar' '$REMOTE_WEB_ROOT/wp-sync-deploy.tasks.php'" </dev/null

	logSuccess "WP-CLI available on the remote server."
}

# Run WP-CLI locally, forwarding all arguments.
# Uses the cached phar with deprecation notices hidden, like wpRemote
function wpLocal() {
	cacheWpCli
	php -d error_reporting=24575 "$WP_CLI_LOCAL_PHAR" --require="$SCRIPT_DIR/lib/wp-cli-setup.php" "$@"
}

# Deactivate maintenance mode if the script exits before doing so, e.g. on errors or Ctrl-C.
# Deletes the .maintenance file directly, as WordPress might not load after an interrupted import
function cleanupMaintenanceMode() {
	case "${MAINTENANCE_MODE:-}" in
	local) rm -f "$LOCAL_ROOT_DIR/$WP_CORE_DIR/.maintenance" ;;
	remote) $SSH_CONNECTION "rm -f '$REMOTE_ROOT_DIR/$WP_CORE_DIR/.maintenance'" </dev/null ;;
	*) return 0 ;;
	esac
	log "🔧 Deactivated maintenance mode at $MAINTENANCE_MODE"
}

# Close the shared SSH connection
function closeSshConnection() {
	[ -S "${SSH_CONTROL_PATH:-}" ] || return 0
	ssh -o ControlPath="$SSH_CONTROL_PATH" -O exit "$REMOTE_SSH" 2>/dev/null || true
}

# Run wp cli on a remote server, forwarding all arguments
function wpRemote() {
	local ARGS="$@"

	# Install WP-CLI on remote server
	installRemoteWpCli

	# Log an empty line
	logLine

	# Construct the remote command
	local REMOTE_COMMAND="$SSH_CONNECTION 'cd $REMOTE_WEB_ROOT && $REMOTE_PHP_BINARY -d error_reporting=24575 ~/$REMOTE_FILES_DIR/wp-cli.phar --require=\$HOME/$REMOTE_FILES_DIR/wp-cli-setup.php --url=$REMOTE_URL $ARGS'"

	# @see ChatGPT
	eval $REMOTE_COMMAND
}

# Runs the task file on the remote server
function runRemoteTasks() {
	[ ! -e "$TASKS_FILE" ] && return

	local TASK="$1"

	log "Running ${BLUE}wp eval-file wp-sync-deploy.tasks.php $TASK${NC} on $PRETTY_REMOTE_ENV server ... \n"

	# Upload the file next to WP-CLI, which also creates the remote dir
	installRemoteWpCli
	rsync -e "$SSH_COMMAND" -q "$TASKS_FILE" "$REMOTE_SSH:$REMOTE_FILES_DIR/"

	# Execute the file on the remote server, passing in the current $TASK ("deploy" or "sync")
	local STATUS=0
	wpRemote eval-file "~/$REMOTE_FILES_DIR/wp-sync-deploy.tasks.php" "$TASK" || STATUS=$?

	# Delete the file from the remote server, even if a task failed
	$SSH_CONNECTION "rm -f ~/$REMOTE_FILES_DIR/wp-sync-deploy.tasks.php" </dev/null

	return $STATUS
}

# Pull the remote database into the local database
function pullDatabase() {
	# Confirmation dialog
	log "🔄 Would you really like to 💥 ${RED}reset the local database${NC} ($PRETTY_LOCAL_HOST)"
	log "and sync from ${BOLD}$REMOTE_ENV${NORMAL} ($PRETTY_REMOTE_HOST)?"
	read -r -p " [y/n] " PROMPT_RESPONSE

	# Return early if not confirmed
	[[ "$PROMPT_RESPONSE" != "y" ]] && exit 1

	# Activate maintenance mode
	wpLocal maintenance-mode activate --quiet
	logSuccess "Maintenance mode activated at $PRETTY_LOCAL_ENV"
	MAINTENANCE_MODE=local

	# Import the remote database into the local database
	# Removes lines containing '999999' followed by 'enable the sandbox'
	# @see https://mariadb.org/mariadb-dump-file-compatibility-change/
	wpRemote db export --default-character-set=utf8mb4 - | sed '/999999.*enable the sandbox/d' | wpLocal db import -

	# Replace the remote URL with the local URL
	log "🔄 Replacing ${BLUE}$REMOTE_HOST${NC} with ${BLUE}$LOCAL_HOST${NC} ..."
	logLine
	wpLocal search-replace "//$REMOTE_HOST" "//$LOCAL_HOST" --all-tables-with-prefix --report-changed-only
	# Multisite: replace the bare domains in the network tables
	wpLocal search-replace "$REMOTE_HOST" "$LOCAL_HOST" --all-tables-with-prefix --include-columns=domain --quiet

	# Deactivate maintenance mode
	wpLocal maintenance-mode deactivate --quiet
	logSuccess "Maintenance mode deactivated at $PRETTY_LOCAL_ENV"
	logLine
	MAINTENANCE_MODE=""

	# Run tasks on the local server
	[ -e "$TASKS_FILE" ] && wpLocal eval-file "$TASKS_FILE" sync

	# Delete local transients
	wpLocal transient delete --all

	logSuccess "Database imported from ${GREEN}$REMOTE_URL${NC} to ${GREEN}$LOCAL_URL${NC}"
}

# Backup a remote database and store it locally
function backupDatabase() {
	local NAME="$REMOTE_HOST-$(date +"%Y-%m-%d_%H-%M-%S").sql"
	wpRemote db export --default-character-set=utf8mb4 - | sed '/999999.*enable the sandbox/d' >"$NAME"
	logSuccess "Database backup saved to ${GREEN}$NAME${NC}"
}

# Push the local database to the remote environment
function pushDatabase() {

	[ "$REMOTE_ENV" == "production" ] && logError "Syncing to the production database is not allowed for security reasons"

	# Confirmation dialog
	log "🚨 Would you really like to 💥 ${RED}reset the $REMOTE_ENV database${NC} ($PRETTY_REMOTE_HOST)"
	log "and ${RED}push from local${NC}?"
	read -r -p " Type 'push' to continue ... " PROMPT_RESPONSE

	# Return early if not confirmed
	[[ "$PROMPT_RESPONSE" != "push" ]] && logError "Permission denied, aborting ..."

	# Activate maintenance mode on the remote server
	wpRemote maintenance-mode activate --quiet &&
		logSuccess "Maintenance mode activated at $PRETTY_REMOTE_ENV" &&
		MAINTENANCE_MODE=remote &&

		# Import the local database into the remote database
		wpLocal db export --default-character-set=utf8mb4 - | wpRemote db import - &&

		# Replace the local URL with the remote URL
		log "🔄 Replacing ${BLUE}$LOCAL_HOST${NC} with ${BLUE}$REMOTE_HOST${NC} ..." &&
		wpRemote search-replace "//$LOCAL_HOST" "//$REMOTE_HOST" --all-tables-with-prefix --report-changed-only &&

		# Multisite: replace the bare domains in the network tables
		wpRemote search-replace "$LOCAL_HOST" "$REMOTE_HOST" --all-tables-with-prefix --include-columns=domain --quiet

	# Deactivate maintenance mode on the remote server
	wpRemote maintenance-mode deactivate --quiet
	logSuccess "Maintenance mode deactivated at $PRETTY_REMOTE_ENV"
	MAINTENANCE_MODE=""

	# Run tasks on the remote server
	runRemoteTasks sync

	# Delete remote transients
	wpRemote transient delete --all

	logSuccess "Pushed the database from ${GREEN}$LOCAL_URL${NC} to ${GREEN}$REMOTE_URL${NC}"
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

	log "🚨 ${BOLD}${RED}openrsync detected${NC} at ${BLUE}$bin${NC}"
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

# Read the WordPress version from a version.php file passed via stdin
function readWPVersion() {
	sed -n "s/^\$wp_version = '\(.*\)';.*/\1/p"
}

# Abort if the remote WordPress version is newer than the local one
# (e.g. a security update applied on the server), as the deploy would downgrade it.
function checkWPVersions() {
	local VERSION_FILE="$WP_CORE_DIR/wp-includes/version.php"
	local LOCAL_VERSION=$(readWPVersion <"$LOCAL_ROOT_DIR/$VERSION_FILE")
	local REMOTE_VERSION=$($SSH_CONNECTION "cat \"$REMOTE_ROOT_DIR/$VERSION_FILE\" 2>/dev/null" | readWPVersion)

	[[ -z "$LOCAL_VERSION" ]] && logError "Couldn't detect the local WordPress version"
	# Nothing to compare on a fresh remote
	[[ -z "$REMOTE_VERSION" ]] && return 0

	log "   - WordPress version at $PRETTY_LOCAL_ENV: ${BLUE}$LOCAL_VERSION${NC}"
	log "   - WordPress version at $PRETTY_REMOTE_ENV: ${BLUE}$REMOTE_VERSION${NC}"

	local LOWEST=$(printf '%s\n%s\n' "$LOCAL_VERSION" "$REMOTE_VERSION" | sort -V | head -n1)
	if [[ "$LOCAL_VERSION" == "$REMOTE_VERSION" || "$LOWEST" == "$REMOTE_VERSION" ]]; then
		logSuccess "Local WordPress version is up to date"
		return 0
	fi

	logWarning "${BOLD}${RED}WordPress at $PRETTY_REMOTE_ENV is newer than locally${NC}${NORMAL}"
	log "   The deploy will downgrade it from ${BLUE}$REMOTE_VERSION${NC} to ${BLUE}$LOCAL_VERSION${NC}"
	confirmDeploy "WordPress at $PRETTY_REMOTE_ENV is newer than locally"
}

# List all plugins and themes in a content dir as "<key>\t<version>"
# Runs both locally and remotely (via `declare -f`), so keep it self-contained
function listExtensionVersions() {
	cd "$1" 2>/dev/null || return 0
	for file in plugins/*.php plugins/*/*.php themes/*/style.css; do
		[ -f "$file" ] || continue
		key="${file%/*}"
		[ "$key" = "plugins" ] && key="$file"
		head -c 8192 "$file" | awk -v key="$key" '
			tolower($0) ~ /^[ \t\/*#@]*(plugin|theme) name:/ { named = 1 }
			tolower($0) ~ /^[ \t\/*#@]*version:/ && version == "" {
				version = $0
				sub(/^[^:]*:[ \t]*/, "", version)
				sub(/[ \t\r]*$/, "", version)
			}
			END { if (named) print key "\t" version }'
	done | sort -u -t "$(printf '\t')" -k1,1
}

# Ask for confirmation if plugins or themes at the remote are missing locally
# or newer than locally (e.g. updated via wp-admin), as the deploy would remove or downgrade them.
function checkExtensionVersions() {
	local LOCAL_LIST=$(listExtensionVersions "$LOCAL_ROOT_DIR/$WP_CONTENT_DIR")
	local REMOTE_LIST=$({
		declare -f listExtensionVersions
		echo "listExtensionVersions \"$REMOTE_ROOT_DIR/$WP_CONTENT_DIR\""
	} | $SSH_CONNECTION bash -s)

	# Nothing to compare on a fresh remote
	[[ -z "$REMOTE_LIST" ]] && return 0

	local PROBLEMS=""
	local KEY REMOTE_VERSION LOCAL_ENTRY LOCAL_VERSION LOWEST
	while IFS=$'\t' read -r KEY REMOTE_VERSION; do
		LOCAL_ENTRY=$(printf '%s\n' "$LOCAL_LIST" | awk -F'\t' -v key="$KEY" '$1 == key { print "found\t" $2; exit }')

		if [[ -z "$LOCAL_ENTRY" ]]; then
			PROBLEMS="$PROBLEMS\n\r   - ${BLUE}$KEY${NC} ($REMOTE_VERSION) is missing locally and will be deleted"
			continue
		fi

		LOCAL_VERSION="${LOCAL_ENTRY#found$'\t'}"
		[[ -z "$LOCAL_VERSION" || -z "$REMOTE_VERSION" || "$LOCAL_VERSION" == "$REMOTE_VERSION" ]] && continue

		LOWEST=$(printf '%s\n%s\n' "$LOCAL_VERSION" "$REMOTE_VERSION" | sort -V | head -n1)
		[[ "$LOWEST" == "$LOCAL_VERSION" ]] &&
			PROBLEMS="$PROBLEMS\n\r   - ${BLUE}$KEY${NC} will be downgraded from ${BLUE}$REMOTE_VERSION${NC} to ${BLUE}$LOCAL_VERSION${NC}"
	done <<<"$REMOTE_LIST"

	if [[ -z "$PROBLEMS" ]]; then
		logSuccess "Local plugins and themes are up to date"
		return 0
	fi

	logWarning "${BOLD}${RED}Plugins or themes at $PRETTY_REMOTE_ENV differ from local${NC}${NORMAL}$PROBLEMS"
	confirmDeploy "Plugins or themes at $PRETTY_REMOTE_ENV differ from local"
	return 0
}

# Build the composer vendor dir without dev dependencies in a temp dir
# Sets $VENDOR_DIR (relative to the root dir), $COMPOSER_VENDOR_DIR (relative to composer.json) and $VENDOR_BUILD_DIR
function buildVendor() {
	local COMPOSER_ROOT=$(normalizePath "$LOCAL_ROOT_DIR/$COMPOSER_DIR")

	command -v composer >/dev/null || logError "${BLUE}composer${NC} not found"
	[ -f "$COMPOSER_ROOT/composer.json" ] || logError "No composer.json found in ${RED}$COMPOSER_ROOT${NC}"
	[ -f "$COMPOSER_ROOT/composer.lock" ] || logError "No composer.lock found in ${RED}$COMPOSER_ROOT${NC}"

	# Relative path repositories would break in the temp dir
	php -r '$c = json_decode(file_get_contents($argv[1]), true); foreach ($c["repositories"] ?? [] as $r) { if (($r["type"] ?? "") === "path" && !str_starts_with($r["url"] ?? "", "/")) exit(1); }' "$COMPOSER_ROOT/composer.json" ||
		logError "Relative ${BLUE}path${NC} repositories in composer.json are not supported"

	COMPOSER_VENDOR_DIR=$(composer config vendor-dir --working-dir="$COMPOSER_ROOT")
	[[ "$COMPOSER_VENDOR_DIR" == /* ]] && logError "Absolute composer vendor-dir is not supported: ${RED}$COMPOSER_VENDOR_DIR${NC}"
	VENDOR_DIR=$(relativePath $(normalizePath "$COMPOSER_DIR/$COMPOSER_VENDOR_DIR"))

	# Prevent deploying the vendor dir twice
	for DIR in ${ADDITIONAL_DIRS:-}; do
		[[ "$(relativePath $(normalizePath "$DIR"))" == "$VENDOR_DIR" ]] &&
			logError "Remove ${RED}$DIR${NC} from additional paths, it is deployed through ${BLUE}composer${NC}"
	done

	VENDOR_BUILD_DIR=$(mktemp -d)
	cp "$COMPOSER_ROOT/composer.json" "$COMPOSER_ROOT/composer.lock" "$VENDOR_BUILD_DIR/"
	[ -f "$COMPOSER_ROOT/auth.json" ] && cp "$COMPOSER_ROOT/auth.json" "$VENDOR_BUILD_DIR/"

	log "📦 Building ${BLUE}$VENDOR_DIR${NC} without dev dependencies ..."
	composer install --working-dir="$VENDOR_BUILD_DIR" \
		--no-dev --no-scripts --no-interaction --no-progress --optimize-autoloader --quiet ||
		logError "composer install failed"
	logSuccess "Built ${BLUE}$VENDOR_DIR${NC}"
}

# Deploy the vendor dir built by buildVendor
# Usage: deployVendor [--dry-run]
function deployVendor() {
	"$RSYNC_BIN" "$@" -avz --delete \
		--chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r \
		-e "$SSH_COMMAND" \
		--filter="merge $IGNORE_FILE" \
		"$VENDOR_BUILD_DIR/$COMPOSER_VENDOR_DIR/" "$REMOTE_SSH:$REMOTE_ROOT_DIR/$VENDOR_DIR/"
}

# List the files in $DEPLOY_PATHS matching a pattern that a deploy would transfer.
# rsync applies the ignore rules, so ignored files and folders are skipped
function listDeployedFiles() {
	local DEST=$(mktemp -d)
	(cd "$LOCAL_ROOT_DIR" && "$RSYNC_BIN" --dry-run -r --relative --out-format='%n' \
		--filter="merge $IGNORE_FILE" --include='*/' --include="$1" --exclude='*' \
		$DEPLOY_PATHS "$DEST/") | grep -v '/$'
	rmdir "$DEST"
}

# Ask for confirmation if the project's deployed vendor dirs (root or git repo) contain dev packages.
# Third-party plugins often ship their own, which isn't ours to fix
function checkVendorDevPackages() {
	local FILE VENDOR DIR COUNT SUGGESTION PROBLEMS=""
	local GIT_PATH=$(relativePath "$(normalizePath "${GIT_DIR:-}")")
	while IFS= read -r FILE; do
		VENDOR=$(dirname "$(dirname "$FILE")")
		DIR=$(dirname "$VENDOR")
		[[ "$DIR" == "." || ( -n "${GIT_DIR+x}" && "$DIR" == "$GIT_PATH" ) ]] || continue
		# Deployed without dev packages through new Composer()
		[[ -n "${COMPOSER_DIR+x}" && "$DIR" == "$(relativePath "$(normalizePath "$COMPOSER_DIR")")" ]] && continue

		COUNT=$(php -r 'echo count(json_decode(file_get_contents($argv[1]), true)["dev-package-names"] ?? []);' "$LOCAL_ROOT_DIR/$FILE")
		[[ "$COUNT" == "0" ]] && continue

		SUGGESTION="new Composer()"
		[[ "$DIR" != "." ]] && SUGGESTION="new Composer(dir: '$DIR')"
		PROBLEMS="$PROBLEMS\n\r   - ${BLUE}$VENDOR${NC} contains ${RED}$COUNT${NC} dev package(s). Use ${BLUE}composer: $SUGGESTION${NC} to deploy it without them"
	done < <(listDeployedFiles 'vendor/composer/installed.json')

	[[ -z "$PROBLEMS" ]] && return 0

	logWarning "${BOLD}${RED}Composer dev dependencies will be deployed${NC}${NORMAL}$PROBLEMS"
	confirmDeploy "Composer dev dependencies will be deployed"
}


# Append rules for `export-ignore` in .gitattributes files inside the deploy paths to $IGNORE_FILE
function addGitattributesIgnores() {
	[[ "$IGNORE_GITATTRIBUTES" != "1" ]] && return 0

	local FILE DIR PATTERN ATTRS RULES=""
	while IFS= read -r FILE; do
		DIR=$(dirname "$FILE")
		while read -r PATTERN ATTRS || [[ -n "$PATTERN" ]]; do
			[[ -z "$PATTERN" || "$PATTERN" == \#* ]] && continue
			[[ " $ATTRS " == *" export-ignore "* ]] || continue
			PATTERN="${PATTERN%/}"
			if [[ "$PATTERN" == /* ]]; then
				RULES="$RULES-p /$DIR$PATTERN\n"
			elif [[ "$PATTERN" == */* ]]; then
				RULES="$RULES-p /$DIR/$PATTERN\n"
			else
				# Patterns without a slash match at any depth
				RULES="$RULES-p /$DIR/$PATTERN\n-p /$DIR/**/$PATTERN\n"
			fi
		done <"$LOCAL_ROOT_DIR/$FILE"
	done < <(cd "$LOCAL_ROOT_DIR" && find $DEPLOY_PATHS \( -name node_modules -o -name vendor \) -prune -o -name .gitattributes -print 2>/dev/null)

	[[ -z "$RULES" ]] && return 0
	printf '%b' "$RULES" >>"$IGNORE_FILE"
	log "ℹ️  Ignoring files marked as ${BLUE}export-ignore${NC} in .gitattributes"
}

# List remote folders rsync couldn't delete because of ignored files inside
function logLeftovers() {
	local LEFTOVERS
	LEFTOVERS=$({
		sed -n 's/^cannot delete non-empty directory: //p' "$RSYNC_LOG"
		sed -n "s|^cannot delete non-empty directory: |${VENDOR_DIR:-vendor}/|p" "$VENDOR_RSYNC_LOG"
	} | sort -u | sed 's/^/   - /')
	[[ -z "$LEFTOVERS" ]] && return 0
	log "🧹 ${BOLD}Can't be deleted at $PRETTY_REMOTE_ENV because of ignored files inside, clean up manually:${NORMAL}\n\r$LEFTOVERS"
}
