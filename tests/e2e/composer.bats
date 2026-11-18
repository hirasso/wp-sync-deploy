#!/usr/bin/env bats

load helpers

LIB=/srv/e2e-lib
VENDOR=/srv/staging/vendor/e2e/lib

# Release a version of the local package and update the project's vendor dir
releaseLib() {
	printf '{"name": "e2e/lib", "version": "%s"}\n' "$1" >"$LIB/composer.json"
	echo "$1" >"$LIB/version.txt"
	composer update --working-dir="$LOCAL" --quiet --no-interaction
}

setup_file() {
	resetSites
	sudo rm -rf "$LIB" && sudo install -d -o dev -g dev "$LIB"
	cat >"$LOCAL/composer.json" <<EOF
{
    "repositories": [{"type": "path", "url": "$LIB", "options": {"symlink": false}}, {"packagist.org": false}],
    "require": {"e2e/lib": "*"}
}
EOF
	sed -i 's|^);|    composer: new \\Hirasso\\WPSyncDeploy\\Composer(),\n);|' "$LOCAL/wp-sync-deploy.config.php"
	releaseLib 1.0.0
	wsd deploy staging --yes
}

@test "deploy creates the vendor dir" {
	[ "$(cat "$VENDOR/version.txt")" = 1.0.0 ]
}

@test "rollback restores the vendor dir" {
	echo new >"$LIB/new.txt"
	releaseLib 1.1.0
	wsd deploy staging --yes
	[ "$(cat "$VENDOR/version.txt")" = 1.1.0 ]
	[ -e "$VENDOR/new.txt" ]

	run wsd rollback staging --yes
	[ "$status" -eq 0 ]
	[ "$(cat "$VENDOR/version.txt")" = 1.0.0 ]
	[ ! -e "$VENDOR/new.txt" ]
}

@test "rollback removes a vendor dir the deploy created" {
	run wsd rollback staging --yes
	[ "$status" -eq 0 ]
	[ ! -e "$VENDOR" ]
}
