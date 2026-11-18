#!/usr/bin/env bats

load helpers

setup_file() {
	resetSites
}

@test "pull replaces the local database and hosts" {
	run wsdConfirm sync production
	[ "$status" -eq 0 ]
	wpAt local post list --field=post_name | grep -qx post-on-prod
	[ "$(wpAt local option get home)" = http://local.test ]
	curl -s http://local.test/post-on-prod/ | head -c 600
	wpAt local option get permalink_structure
	[ "$(httpStatus http://local.test/post-on-prod/)" = 200 ]
}

@test "backup saves the remote database locally" {
	run wsd sync production backup
	[ "$status" -eq 0 ]
	ls "$LOCAL"/prod.test-*.sql
	grep -q post-on-prod "$LOCAL"/prod.test-*.sql
}

@test "push to production is refused" {
	run wsd sync production push
	[ "$status" -ne 0 ]
	[[ "$output" == *"not allowed"* ]]
}

@test "pull doesn't lock the remote tables" {
	mariadb prod -e "CREATE TABLE wp_e2e_filler (v TEXT) ENGINE=InnoDB;
		INSERT INTO wp_e2e_filler SELECT REPEAT(MD5(seq), 8) FROM seq_1_to_300000;"
	local log="$BATS_TEST_TMPDIR/sync.log"
	wsdConfirm sync production >"$log" 2>&1 &
	local pid=$!

	dumping() {
		mariadb -N -e "SELECT COUNT(*) FROM information_schema.processlist WHERE db = 'prod' AND info LIKE 'SELECT%'" | grep -qv '^0$'
	}
	for _ in $(seq 100); do dumping && break; sleep 0.1; done
	dumping

	# Blocks until the dump finishes if it locks the tables
	mariadb prod -e "SET SESSION lock_wait_timeout = 2; SET SESSION innodb_lock_wait_timeout = 2;
		UPDATE wp_options SET option_value = 'written during dump' WHERE option_name = 'blogname'"
	# Otherwise the test proves nothing: make the filler table bigger
	dumping

	wait "$pid" || { cat "$log"; false; }
}
