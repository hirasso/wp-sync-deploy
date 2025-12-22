<?php

/**
 * This file can be used as a starting point for adding custom code
 * that should be executed on the target server after each sync or deploy.
 *
 * @see https://github.com/hirasso/wp-sync-deploy#run-automated-tasks-after-each-deploy--sync-
 *
 * Debug this file for sync tasks:
 * `wp eval-file wp-sync-deploy.tasks.php sync`
 *
 * Debug this file for deploy tasks:
 * `wp eval-file wp-sync-deploy.tasks.php deploy`
 */

/** Feel free to change the namespace to whatever */

namespace WPSyncDeploy\Tasks;

/** Exit if accessed directly */
!defined('ABSPATH') && exit;

/** The web host of this install */
$host = wp_parse_url(home_url())['host'];

/** The current task, either 'sync' or 'deploy' */
$task = $args[0] ?? '';
!in_array($task, ['sync', 'deploy']) && \WP_CLI::error("\$task must either be 'sync' or 'deploy'");

/**
 * Ask a question in WP_CLI
 * @see https://www.ibenic.com/useful-interactive-prompts-wp-cli-commands/
 * @see https://make.wordpress.org/cli/handbook/references/internal-api/wp-cli-colorize/#notes
 */
function ask(string $question, string $options = 'y/n')
{
    fwrite(STDOUT, \WP_CLI::colorize("🙋 $question [$options] "));
    return strtolower(trim(fgets(STDIN)));
}

/** Clear all transients */
\WP_CLI::runcommand('transient delete --all');
/** Clear the WP SuperCache cache if it exists */
if (function_exists('wp_cache_clear_cache')) {
    wp_cache_clear_cache();
    \WP_CLI::success('Cleared WP Super Cache cache');
}

/**
 * Run tasks anytime you deploy
 */
if ($task === 'deploy') {
    /** Activate all plugins */
    \WP_CLI::runcommand('plugin activate --all');
    /** Update the database */
    \WP_CLI::runcommand('core update-db');
    /** Flush the rewrite rules */
    \WP_CLI::runcommand('rewrite flush');
}
