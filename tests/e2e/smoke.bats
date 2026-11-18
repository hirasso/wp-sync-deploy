#!/usr/bin/env bats

load helpers

setup_file() {
	resetSites
}

THEME=public/content/themes/e2e
PLUGIN=public/content/plugins/e2e

# Theme that 404s on single posts only, like broken rewrite rules
break404() {
	echo '<?php if (is_singular()) { status_header(404); } echo "e2e";' >"$LOCAL/$THEME/index.php"
}

restoreTheme() {
	cp "$PACKAGE_DIR/tests/e2e/fixture/$THEME/index.php" "$LOCAL/$THEME/index.php"
}

@test "deploy runs a smoke test" {
	run wsd deploy staging --yes
	[ "$status" -eq 0 ]
	[[ "$output" == *"Smoke test passed (3 URLs)"* ]]
}

@test "dry run doesn't run the smoke test" {
	run wsd deploy staging --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"Would run a smoke test"* ]]
	[[ "$output" != *"Smoke test passed"* ]]
}

@test "failed smoke test doesn't roll back without consent" {
	break404
	# Risky: no deploy prompt. Closed stdin answers the rollback prompt
	local config="$LOCAL/wp-sync-deploy.config.php"
	cp "$config" "$BATS_TEST_TMPDIR/config.php"
	sed -i "s|rootDir: '/srv/staging',|rootDir: '/srv/staging', deployStrategy: \\\\Hirasso\\\\WPSyncDeploy\\\\DeployStrategy::Risky,|" "$config"

	run wsd deploy staging </dev/null
	cp "$BATS_TEST_TMPDIR/config.php" "$config"
	[ "$status" -ne 0 ]
	[[ "$output" == *"404"*"post-on-staging"* ]]
	[[ "$output" != *"rolled back"* ]]
	[ "$(httpStatus http://staging.test/post-on-staging/)" = 404 ]
}

@test "failed smoke test rolls back automatically with --yes" {
	restoreTheme
	wsd deploy staging --yes
	break404

	run wsd deploy staging --yes
	[ "$status" -ne 0 ]
	[[ "$output" == *"rolled back"* ]]
	eventuallyStatus http://staging.test/post-on-staging/ 200
}

@test "fatal error on the remote rolls back" {
	restoreTheme
	printf '<?php\n/**\n * Plugin Name: e2e\n */\nif (wp_parse_url(home_url(), PHP_URL_HOST) !== "local.test") { e2e_undefined(); }\n' >"$LOCAL/$PLUGIN/e2e.php"

	run wsd deploy staging --yes
	[ "$status" -ne 0 ]
	[[ "$output" == *"rolled back"* ]]
	eventuallyStatus http://staging.test/ 200
}

@test "failed smoke test without snapshots only reports" {
	cp "$PACKAGE_DIR/tests/e2e/fixture/$PLUGIN/e2e.php" "$LOCAL/$PLUGIN/e2e.php"
	sed -i "s|rootDir: '/srv/staging',|rootDir: '/srv/staging', keepSnapshots: 0,|" "$LOCAL/wp-sync-deploy.config.php"
	break404

	run wsd deploy staging --yes
	[ "$status" -ne 0 ]
	[[ "$output" == *"No snapshot"* ]]
	[ "$(httpStatus http://staging.test/post-on-staging/)" = 404 ]
}

@test "rollback runs a smoke test" {
	sed -i "s|keepSnapshots: 0,||" "$LOCAL/wp-sync-deploy.config.php"
	restoreTheme
	wsd deploy staging --yes
	wsd deploy staging --yes

	run wsd rollback staging --yes
	[ "$status" -eq 0 ]
	[[ "$output" == *"Smoke test passed"* ]]
}
