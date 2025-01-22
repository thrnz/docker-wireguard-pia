#!/bin/bash

# By default, only do checks that don't generate any traffic
[[ "$ACTIVE_HEALTHCHECKS" =~ ^[0-1]$ ]] || ACTIVE_HEALTHCHECKS=0
HEALTHCHECK_PING_TARGET="${HEALTHCHECK_PING_TARGET:-www.privateinternetaccess.com}"

wg show wg0 || exit 1

if [ "$PORT_FORWARDING" = "1" ]; then
    pidof pf.sh || exit 1
fi

if [ "$ACTIVE_HEALTHCHECKS" = "1" ]; then
    ping -c 1 -w 2 -I wg0 "$HEALTHCHECK_PING_TARGET" || exit 1
fi