#!/bin/sh

(exec supervisord -c /etc/supervisor/supervisord.ini) &

exec /usr/local/bin/frankenphp run --config /etc/caddy/Caddyfile --adapter caddyfile /app