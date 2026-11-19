#!/usr/bin/env bats

load helpers

setup_file() {
	resetSites
}

# Read by checkMinimumSelfVersion, relative to packages/wp-sync-deploy
fakeInstalledVersion() {
	mkdir -p "$LOCAL/composer"
	printf '{"packages": [{\n"name": "hirasso/wp-sync-deploy",\n"version": "%s"\n}]}\n' "$1" >"$LOCAL/composer/installed.json"
}

teardown() {
	rm -rf "$LOCAL/composer"
}

@test "outdated version continues when confirmed" {
	fakeInstalledVersion 0.0.1
	run wsdConfirm deploy staging --dry-run
	[[ "$output" == *"is outdated"* ]]
	[ "$status" -eq 0 ]
}

@test "outdated version exits when not confirmed" {
	fakeInstalledVersion 0.0.1
	run wsdAnswer n deploy staging --dry-run
	[[ "$output" == *"is outdated"* ]]
	[ "$status" -eq 1 ]
}
