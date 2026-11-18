#!/usr/bin/env bats

load helpers

setup_file() {
	resetSites
}

THEME=public/content/themes/e2e

@test "dry run changes nothing" {
	echo new >"$LOCAL/$THEME/new.php"

	run wsd deploy staging --dry-run
	[ "$status" -eq 0 ]
	[ ! -e "/srv/staging/$THEME/new.php" ]
}

@test "deploy transfers new, changed and deleted files" {
	echo new >"$LOCAL/$THEME/new.php"
	echo '/* changed */' >>"$LOCAL/$THEME/style.css"
	rm "$LOCAL/public/content/plugins/e2e/obsolete.php"
	asDeploy "mkdir -p /srv/staging/public/content/uploads && touch /srv/staging/public/content/uploads/keep.jpg"

	run wsd deploy staging --yes
	[ "$status" -eq 0 ]
	[ -e "/srv/staging/$THEME/new.php" ]
	grep -q changed "/srv/staging/$THEME/style.css"
	[ ! -e /srv/staging/public/content/plugins/e2e/obsolete.php ]
	[ -e /srv/staging/public/content/uploads/keep.jpg ]
	grep -q "'staging'" /srv/staging/public/wp-config.php
}

@test "deploy runs the tasks" {
	run wsd deploy staging --yes
	[ "$status" -eq 0 ]
	[[ "$output" == *"Reset the rewrite rules"* ]]
	[ "$(httpStatus http://staging.test/post-on-staging/)" = 200 ]
}

@test "deploy to production requires .allow-deployment" {
	commitLocal
	asDeploy "rm /srv/prod/.allow-deployment"

	run wsd deploy production --yes
	asDeploy "touch /srv/prod/.allow-deployment"
	[ "$status" -ne 0 ]
	[[ "$output" == *".allow-deployment"* ]]
}

@test "deploy to production" {
	run wsd deploy production --yes
	[ "$status" -eq 0 ]
	[ -e "/srv/prod/$THEME/new.php" ]
	[ "$(httpStatus http://prod.test/post-on-prod/)" = 200 ]
}

@test "deploy works if composer's installed.json lacks the package" {
	# The package is in packages/wp-sync-deploy, see installPackage
	mkdir -p "$LOCAL/composer"
	echo '{"packages": []}' >"$LOCAL/composer/installed.json"

	run wsd deploy staging --dry-run
	rm -r "$LOCAL/composer"
	[ "$status" -eq 0 ]
}
