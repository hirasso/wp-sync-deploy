<?php

/**
 * Hide PHP deprecation notices in WP-CLI, loaded with `--require`.
 * `-d error_reporting` isn't enough, as WordPress resets it (e.g. to E_ALL with WP_DEBUG)
 */
set_error_handler(fn () => true, E_DEPRECATED | E_USER_DEPRECATED);
