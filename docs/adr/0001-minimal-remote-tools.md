# Minimal remote tools

Status: accepted

Shared hosters often give SSH users a jailed shell with only a handful of binaries (one lacked `xargs`, failing every deploy after it went live). So commands that run on the remote only rely on:

- POSIX `sh` and its builtins (no `bash`)
- `cat`, `ls`, `mkdir`, `rm`, `rmdir`
- `rsync`, `php` and the MySQL client tools WP-CLI uses (unavoidable anyway)

Everything else is done with shell globs and loops (sorted snapshot dirs), PHP piped to `php --` (gzip, filtering a dump) or WP-CLI (plugin and theme versions, with `--skip-plugins --skip-themes` so a broken one doesn't matter). Local commands may use any common tool.

The e2e remote's login shell (`tests/e2e/docker/jailsh`) only has these tools on its `PATH`, so a new remote dependency fails the tests.
