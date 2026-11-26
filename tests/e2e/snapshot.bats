#!/usr/bin/env bats

load helpers

setup_file() {
	resetSites
}

THEME=public/content/themes/e2e

# Snapshot dirs of a remote, oldest first
snapshots() {
	sudo ls -1 "/home/deploy/.wp-sync-deploy/snapshots/srv-$1" 2>/dev/null || true
}

latestSnapshot() {
	echo "/home/deploy/.wp-sync-deploy/snapshots/srv-$1/$(snapshots "$1" | tail -1)"
}

# Set an option of the staging remote in the local config
setStagingOption() {
	sed -i "s|rootDir: '/srv/staging',|rootDir: '/srv/staging', ${1//\\/\\\\},|" "$LOCAL/wp-sync-deploy.config.php"
}

@test "dry run doesn't snapshot" {
	run wsd deploy staging --dry-run
	[ "$status" -eq 0 ]
	[ -z "$(snapshots staging)" ]
}

@test "deploy snapshots overwritten and deleted files, the database and added files" {
	echo new >"$LOCAL/$THEME/new.php"
	echo '/* changed */' >>"$LOCAL/$THEME/style.css"
	rm "$LOCAL/public/content/plugins/e2e/obsolete.php"

	run wsd deploy staging --yes
	[ "$status" -eq 0 ]
	[ "$(snapshots staging | wc -l)" -eq 1 ]

	local dir=$(latestSnapshot staging)
	[ "$(sudo stat -c %a "$dir")" = 700 ]
	sudo test -e "$dir/files/$THEME/style.css"
	! sudo grep -q changed "$dir/files/$THEME/style.css" || false
	sudo test -e "$dir/files/public/content/plugins/e2e/obsolete.php"
	! sudo test -e "$dir/files/$THEME/new.php" || false
	sudo zcat "$dir/db.sql.gz" | grep -q post-on-staging
	sudo grep -qx "$THEME/new.php" "$dir/added"
	sudo grep -qx "commit=$(git -C "$LOCAL" rev-parse HEAD)" "$dir/manifest"
}

# Like cPanel docroots (user:nobody)
@test "deploy snapshots dirs owned by a group the SSH user isn't in" {
	sudo chgrp nogroup /srv/staging/public
	echo '/* changed again */' >>"$LOCAL/$THEME/style.css"

	run wsd deploy staging --yes
	[ "$status" -eq 0 ]
	[ "$(stat -c %G /srv/staging/public)" = nogroup ]
}

@test "deploy keeps the 2 newest snapshots" {
	echo one >"$LOCAL/$THEME/one.php"
	wsd deploy staging --yes
	echo two >"$LOCAL/$THEME/two.php"
	wsd deploy staging --yes

	[ "$(snapshots staging | wc -l)" -eq 2 ]
	sudo grep -qx "$THEME/two.php" "$(latestSnapshot staging)/added"
}

@test "risky deploys snapshot too" {
	setStagingOption 'deployStrategy: \Hirasso\WPSyncDeploy\DeployStrategy::Risky'
	local before=$(latestSnapshot staging)
	echo three >"$LOCAL/$THEME/three.php"

	run wsd deploy staging
	[ "$status" -eq 0 ]
	[ "$(latestSnapshot staging)" != "$before" ]
}

@test "keepSnapshots: 0 disables snapshots" {
	setStagingOption 'keepSnapshots: 0'
	local before=$(snapshots staging)
	echo four >"$LOCAL/$THEME/four.php"

	run wsd deploy staging --yes
	[ "$status" -eq 0 ]
	[ "$(snapshots staging)" = "$before" ]
}
