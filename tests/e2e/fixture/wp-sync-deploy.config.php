<?php

use Hirasso\WPSyncDeploy\Config;
use Hirasso\WPSyncDeploy\Local;
use Hirasso\WPSyncDeploy\Paths;
use Hirasso\WPSyncDeploy\Remote;

return new Config(
    local: new Local(
        url: 'http://local.test',
        rootDir: __DIR__,
    ),
    paths: new Paths(
        wpContent: 'public/content',
        wpCore: 'public/wp',
        public: 'public',
        additional: ['wp-cli.yml'],
    ),
    production: new Remote(
        url: 'http://prod.test',
        ssh: 'deploy@localhost',
        rootDir: '/srv/prod',
    ),
    staging: new Remote(
        url: 'http://staging.test',
        ssh: 'deploy@localhost',
        rootDir: '/srv/staging',
    ),
);
