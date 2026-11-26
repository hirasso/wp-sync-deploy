#!/usr/bin/env bats

load helpers

setup_file() {
	resetSites
}

THEME=public/content/themes/e2e
PLUGIN=public/content/plugins/e2e

snapshotCount() {
	sudo ls -1 /home/deploy/.wp-sync-deploy/snapshots/srv-staging 2>/dev/null | wc -l
}

@test "rollback without a snapshot fails" {
	run wsd rollback staging --yes
	[ "$status" -ne 0 ]
	[[ "$output" == *"No snapshot"* ]]
}

@test "rollback asks for confirmation" {
	echo new >"$LOCAL/$THEME/new.php"
	wsd deploy staging --yes

	run wsdAnswer n rollback staging
	[ "$status" -ne 0 ]
	[ -e "/srv/staging/$THEME/new.php" ]
	[ "$(snapshotCount)" -eq 1 ]
}

@test "rollback restores files and database from before the latest deploy" {
	mkdir "$LOCAL/$THEME/dir"
	echo new >"$LOCAL/$THEME/dir/new.php"
	echo '/* changed */' >>"$LOCAL/$THEME/style.css"
	rm "$LOCAL/$PLUGIN/obsolete.php"
	wsd deploy staging --yes
	wpAt staging option add e2e_migrated yes
	wpAt staging db query "CREATE TABLE wp_e2e_new (id INT)"
	wpAt staging db query "CREATE TABLE other_app (id INT)"
	wpAt staging post create --post_status=publish --post_title="After deploy" --post_name=after-deploy

	run wsd rollback staging --yes
	[ "$status" -eq 0 ]
	[ ! -e "/srv/staging/$THEME/dir" ]
	[ -e "/srv/staging/$THEME/new.php" ]
	! grep -q changed "/srv/staging/$THEME/style.css" || false
	[ -e "/srv/staging/$PLUGIN/obsolete.php" ]
	! wpAt staging option get e2e_migrated || false
	! wpAt staging db query "SHOW TABLES" --skip-column-names | grep -qx wp_e2e_new || false
	wpAt staging db query "SHOW TABLES" --skip-column-names | grep -qx other_app
	! wpAt staging post list --field=post_name | grep -qx after-deploy || false
	[ ! -e /srv/staging/public/wp/.maintenance ]
	[ "$(httpStatus http://staging.test/post-on-staging/)" = 200 ]
	[ "$(snapshotCount)" -eq 1 ]
}

@test "rollback again goes back one more deploy" {
	run wsd rollback staging --yes
	[ "$status" -eq 0 ]
	[ ! -e "/srv/staging/$THEME/new.php" ]
	[ "$(snapshotCount)" -eq 0 ]
}

@test "rollback keeps owner and permissions of existing dirs" {
	sudo chgrp nogroup /srv/staging /srv/staging/public
	sudo chmod 751 /srv/staging
	echo '/* changed */' >>"$LOCAL/$THEME/style.css"
	wsd deploy staging --yes

	run wsd rollback staging --yes
	[ "$status" -eq 0 ]
	[ "$(stat -c '%a %G' /srv/staging)" = '751 nogroup' ]
	[ "$(stat -c %G /srv/staging/public)" = nogroup ]
}
