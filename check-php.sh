#!/usr/bin/env bash

# Make this script more strict
set -o errexit
set -o nounset
set -o pipefail

# The file name for the PHP check. Appends a hash to make the file hard to detect.
# The file will be automatically deleted after this script finishes
HASH=$(echo $(date +%s%N) | sha256sum | head -c 10)
FILE_NAME="___wp-sync-deploy-php-version-$HASH.php"

# Get the local PHP Version
echo "<?= substr(phpversion(), 0, 3);" > "./$FILE_NAME"
LOCAL_VERSION=$(curl -s "https://$DEV_URL/$FILE_NAME")
printf "\r\n- PHP version at $DEV_URL: ${GREEN}$LOCAL_VERSION${NC}"

# Write a file to the web root that prints the php version
ssh "$SSH_USER@$SSH_HOST" "cd $SSH_PATH; echo '<?= substr(phpversion(), 0, 3);' > ./$FILE_NAME"

# Get the version using CURL
REMOTE_VERSION=$(curl -s "https://$REMOTE_URL/$FILE_NAME")
printf "\r\n- PHP version at $REMOTE_URL: ${GREEN}$REMOTE_VERSION${NC}"

# Remove the file to prevent security issues
ssh "$SSH_USER@$SSH_HOST" "cd $SSH_PATH; rm ./$FILE_NAME"

# Error out if the two PHP versions aren't a match
if [[ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]]; then
  printf "\n🚨${BOLD}${RED} PHP Version mismatch, aborting";
  exit 1;
fi
