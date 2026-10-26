<?php

/**
 * Load a wp-sync-deploy.config.php file and print it as shell variables
 * Usage: `php lib/config.php <file>`
 */

require_once dirname(__DIR__) . '/src/Config.php';

try {
    $config = require $argv[1];
} catch (Throwable $e) {
    fwrite(STDERR, $e->getMessage() . PHP_EOL);
    exit(1);
}

if (!$config instanceof Hirasso\WPSyncDeploy\Config) {
    fwrite(STDERR, 'The config file must return an instance of Hirasso\WPSyncDeploy\Config' . PHP_EOL);
    exit(1);
}

echo $config->toShell();
