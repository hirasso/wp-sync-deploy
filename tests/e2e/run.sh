#!/usr/bin/env bash
# Run the e2e tests in Docker. Arguments go to bats, e.g. `tests/e2e/run.sh deploy.bats`
set -e

cd "$(dirname "$0")"
docker compose up -d --build --wait --quiet-pull

[ $# -eq 0 ] && set -- .
TTY=$([ -t 1 ] || echo -T)
docker compose exec $TTY -u dev -w /opt/wp-sync-deploy/tests/e2e wp bats --print-output-on-failure "$@"
