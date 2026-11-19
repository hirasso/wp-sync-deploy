#!/usr/bin/env bats

load helpers

setup_file() {
	resetSites
}

PLUGIN=public/content/plugins/e2e/e2e.php

@test "deploy asks before downgrading or deleting remote plugins, even if one is broken" {
	sed -i 's|^ \* Plugin Name: e2e$|&\n * Version: 1.0|' "$LOCAL/$PLUGIN"
	asDeploy "sed -i 's|^ \* Plugin Name: e2e\$|&\n * Version: 2.0|' /srv/staging/$PLUGIN"
	asDeploy "mkdir -p /srv/staging/public/content/plugins/broken && printf '%s\n' '<?php' '/** Plugin Name: broken */' 'throw new Error();' >/srv/staging/public/content/plugins/broken/broken.php"
	wpAt staging option update active_plugins '["e2e/e2e.php","broken/broken.php"]' --format=json --quiet

	run wsdAnswer n deploy staging
	[ "$status" -ne 0 ]
	[[ "$output" == *"e2e will be downgraded from 2.0 to 1.0"* ]]
	[[ "$output" == *"broken () is missing locally"* ]]
	[ -e /srv/staging/public/content/plugins/broken/broken.php ]
}

@test "deploy skips the plugin check if WP-CLI fails on the remote" {
	asDeploy "mv /srv/staging/public/wp-config.php /srv/staging/public/wp-config.php.bak"

	run wsdAnswer n deploy staging --dry-run
	asDeploy "mv /srv/staging/public/wp-config.php.bak /srv/staging/public/wp-config.php"
	[ "$status" -eq 0 ]
	[[ "$output" == *"skipping their version check"* ]]
}
