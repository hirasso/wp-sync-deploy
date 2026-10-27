<?php

/**
 * Set up WP-CLI for wp-sync-deploy, loaded with `--require`.
 */

/**
 * Hide PHP deprecation notices.
 * `-d error_reporting` isn't enough, as WordPress resets it (e.g. to E_ALL with WP_DEBUG)
 */
set_error_handler(fn () => true, E_DEPRECATED | E_USER_DEPRECATED);

/**
 * Log like wp-sync-deploy: symbols instead of "Success:", "Warning:" and "Error:".
 * The logger is initialized before `--require` files are loaded. `--quiet` keeps its own logger
 */
if (WP_CLI::get_logger() instanceof WP_CLI\Loggers\Regular) {
    WP_CLI::set_logger(new class (WP_CLI::get_runner()->in_color()) extends WP_CLI\Loggers\Regular {
        public function success($message)
        {
            $this->write(STDOUT, WP_CLI::colorize('%g✔%n ') . "$message\n");
        }

        public function warning($message)
        {
            $this->write(STDERR, "⚠️  $message\n");
        }

        public function error($message)
        {
            $this->write(STDERR, "🚨 $message\n");
        }
    });
}
