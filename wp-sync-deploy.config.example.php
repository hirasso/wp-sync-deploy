<?php

/**
 * Configuration for wp-sync-deploy
 *
 * Commit this file. For secrets like http auth credentials, use environment variables.
 *
 * @see https://github.com/hirasso/wp-sync-deploy#configuration
 */

use WPSyncDeploy\Config;
use WPSyncDeploy\DeployStrategy;
use WPSyncDeploy\Git;
use WPSyncDeploy\Local;
use WPSyncDeploy\Paths;
use WPSyncDeploy\Remote;

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
