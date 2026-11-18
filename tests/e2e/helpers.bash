#!/usr/bin/env bash
# Shared setup for the e2e tests. Runs as user `dev` inside the container (see Dockerfile)

PACKAGE_DIR=/opt/wp-sync-deploy
LOCAL=/srv/local

# Run wp-sync-deploy from the local project, like `vendor/bin/wp-sync-deploy`
wsd() {
	(cd "$LOCAL" && vendor/hirasso/wp-sync-deploy/bin/wp-sync-deploy "$@")
}

# Same, answering "y" to the confirmation prompt
wsdConfirm() {
	echo y | wsd "$@"
}

# WP-CLI for an environment: local, staging or prod
wpAt() {
	local site=$1
	shift
	if [ "$site" = local ]; then
		wp --path="/srv/local/public/wp" "$@"
	else
		sudo -u deploy -H wp --path="/srv/$site/public/wp" "$@"
	fi
}

# Run a shell command on a remote, as the SSH user
asDeploy() {
	sudo -u deploy -H bash -c "$1"
}

# HTTP status of a URL
httpStatus() {
	curl -s -o /dev/null -w '%{http_code}' "$1"
}

writeWpConfig() {
	local site=$1
	cat <<EOF
<?php
define('DB_NAME', '$site');
define('DB_USER', 'wp');
define('DB_PASSWORD', 'wp');
define('DB_HOST', '127.0.0.1');
define('WP_HOME', 'http://$site.test');
define('WP_SITEURL', 'http://$site.test/wp');
define('WP_CONTENT_DIR', __DIR__ . '/content');
define('WP_CONTENT_URL', 'http://$site.test/content');
\$table_prefix = 'wp_';
require_once __DIR__ . '/wp/wp-settings.php';
EOF
}

installWordPress() {
	local site=$1
	mariadb -e "DROP DATABASE IF EXISTS $site; CREATE DATABASE $site"
	wpAt "$site" core install --url="http://$site.test" --title="$site" \
		--admin_user=admin --admin_password=admin --admin_email=admin@example.com --skip-email --quiet
	wpAt "$site" theme activate e2e --quiet
	wpAt "$site" plugin activate e2e --quiet
	wpAt "$site" rewrite structure '/%postname%/' --quiet
	wpAt "$site" post create --post_status=publish --post_title="Post on $site" --post_name="post-on-$site" --quiet
}

# Local project (a git repo pushed to its origin) and two remotes, as after a first deploy
resetSites() {
	sudo rm -rf /srv/local /srv/staging /srv/prod /srv/origin.git
	sudo install -d -o dev -g dev /srv/local /srv/origin.git
	sudo install -d -o deploy -g deploy /srv/staging /srv/prod

	cp -R "$PACKAGE_DIR/tests/e2e/fixture/." "$LOCAL/"
	cp -R /opt/wp-core "$LOCAL/public/wp"
	cp "$PACKAGE_DIR/wp-sync-deploy.tasks.example.php" "$LOCAL/wp-sync-deploy.tasks.php"
	writeWpConfig local >"$LOCAL/public/wp-config.php"
	mkdir -p "$LOCAL/vendor/hirasso"
	rsync -a --exclude=.git --exclude=tests "$PACKAGE_DIR/" "$LOCAL/vendor/hirasso/wp-sync-deploy/"
	installWordPress local

	printf '/vendor/\n/public/wp-config.php\n' >"$LOCAL/.gitignore"
	git init -q --bare /srv/origin.git
	git -C "$LOCAL" init -q
	git -C "$LOCAL" add -A
	git -C "$LOCAL" commit -qm init
	git -C "$LOCAL" remote add origin /srv/origin.git
	git -C "$LOCAL" push -q -u origin main

	local site
	for site in staging prod; do
		asDeploy "rsync -a --exclude=.git --exclude=vendor --exclude='wp-sync-deploy.*' $LOCAL/ /srv/$site/"
		writeWpConfig "$site" | asDeploy "cat > /srv/$site/public/wp-config.php"
		asDeploy "touch /srv/$site/.allow-deployment"
		installWordPress "$site"
	done
}

# Commit and push all local changes, so production's git checks pass
commitLocal() {
	git -C "$LOCAL" add -A
	git -C "$LOCAL" commit -qm "${1:-change}"
	git -C "$LOCAL" push -q
}
