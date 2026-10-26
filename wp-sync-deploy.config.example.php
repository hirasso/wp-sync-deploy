<?php

/**
 * Configuration for wp-sync-deploy
 *
 * Commit this file. For secrets like http auth credentials, use environment variables.
 *
 * @see https://github.com/hirasso/wp-sync-deploy#configuration
 */

use Hirasso\WPSyncDeploy\Config;
use Hirasso\WPSyncDeploy\DeployStrategy;
use Hirasso\WPSyncDeploy\Git;
use Hirasso\WPSyncDeploy\Local;
use Hirasso\WPSyncDeploy\Paths;
use Hirasso\WPSyncDeploy\Remote;

return new Config(
    local: new Local(
        url: 'https://example.test',
        rootDir: __DIR__,
    ),
    paths: new Paths(
        wpContent: 'web/app',
        wpCore: 'web/wp',
        public: 'web',
        additional: ['vendor', 'config'],
    ),
    production: new Remote(
        url: 'https://example.com',
        ssh: 'username@example.com',
        rootDir: '/absolute/path/to/production/root',
        deployStrategy: DeployStrategy::Conservative,
    ),
    staging: new Remote(
        url: 'https://staging.example.com',
        ssh: 'username@example.com',
        rootDir: '/absolute/path/to/staging/root',
        httpAuth: getenv('STAGING_HTTP_AUTH') ?: null,
    ),
    git: new Git(
        productionBranch: 'master|main',
    ),
);
