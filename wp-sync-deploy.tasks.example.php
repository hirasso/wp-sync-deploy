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

/**
 * Run a WP-CLI command in this process. Inherits the PHP settings of wp-sync-deploy
 * (e.g. hidden deprecation notices) and is faster than launching a new process
 */
function run(string $command)
{
    \WP_CLI::runcommand($command, ['launch' => false]);
}

/**
 * Activate a theme. Success if it's already active (`wp theme activate` warns then)
 */
function activate_theme(string $stylesheet)
{
    $theme = wp_get_theme($stylesheet);
    $theme->errors() && \WP_CLI::error($theme->errors());
    $name = html_entity_decode($theme->get('Name'), ENT_QUOTES);

    if (get_stylesheet() === $stylesheet) {
        \WP_CLI::success("Theme '$name' is already active");
        return;
    }

    switch_theme($stylesheet);
    \WP_CLI::success("Switched to theme '$name'");
}

/**
 * Reset the rewrite rules of every site. WordPress rebuilds them on the next request,
 * after all plugins ran `init`. `wp rewrite flush` builds them in this process, which
 * misses state a migration just changed (e.g. Polylang's post types), and on multisite
 * only reaches the main site
 */
function reset_rewrite_rules()
{
    if (!is_multisite()) {
        delete_option('rewrite_rules');
    }
    /** switch_to_blog() only exists on multisite */
    foreach (is_multisite() ? get_sites(['fields' => 'ids']) : [] as $id) {
        switch_to_blog($id);
        delete_option('rewrite_rules');
        restore_current_blog();
    }
    \WP_CLI::success('Reset the rewrite rules');
}

/** Clear all transients */
run('transient delete --all');
/** Clear the WP SuperCache cache if it exists */
if (function_exists('wp_cache_clear_cache')) {
    wp_cache_clear_cache();
    \WP_CLI::success('Cleared WP Super Cache cache');
}

/**
 * Run tasks anytime you deploy
 */
if ($task === 'deploy') {
    /** Activate your theme (folder name) */
    // activate_theme('my-theme');
    /** Only if a migration breaks the old code, see `wp help maintenance-mode` */
    // run('maintenance-mode activate');
    /** Update the database */
    run('core update-db');
    // run('maintenance-mode deactivate');
    /** Reset the rewrite rules */
    reset_rewrite_rules();
}
