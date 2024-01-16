<?php

namespace WPSyncDeploy\Taskrunner;

!defined('ABSPATH') && exit; // Exit if accessed directly

/** The web host of this install */
function get_host()
{
    return wp_parse_url(home_url())['host'];
}

/**
 * Ask a question in WP_CLI
 * @see https://www.ibenic.com/useful-interactive-prompts-wp-cli-commands/
 * @see https://make.wordpress.org/cli/handbook/references/internal-api/wp-cli-colorize/#notes
 */
function ask(string $question)
{
    fwrite(STDOUT, \WP_CLI::colorize($question . ' '));
    return strtolower(trim(fgets(STDIN)));
}

/**
 * Clear the cache on this install
 */
function clear_cache()
{
    $host = get_host();
    if (ask("Do you want to clear the cache on %b$host%n? [y/n]") !== 'y') return;

    // delete all transients
    \WP_CLI::runcommand('transient delete --all');
    // clear Super Cache files if the plugin is installed
    function_exists('wp_cache_clear_cache') && wp_cache_clear_cache();
    // ... ???
}
clear_cache();
