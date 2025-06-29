#!/bin/bash

# By default, only do checks that don't generate any traffic
[[ "$ACTIVE_HEALTHCHECKS" =~ ^[0-1]$ ]] || ACTIVE_HEALTHCHECKS=0
HEALTHCHECK_PING_TARGET="${HEALTHCHECK_PING_TARGET:-www.privateinternetaccess.com 1.1.1.1}"
[[ "$HEALTHCHECK_PING_TIMEOUT" =~ ^[0-9]+$ ]] || HEALTHCHECK_PING_TIMEOUT=3

wg show wg0 || exit 1

if [ "$PORT_FORWARDING" = "1" ]; then
    pidof pf.sh || exit 1
fi

if [ "$ACTIVE_HEALTHCHECKS" = "1" ]; then
    success=0
    # Accept comma separated as well as space separated list
    for target in ${HEALTHCHECK_PING_TARGET//,/ }; do
        ping -c 1 -w "$HEALTHCHECK_PING_TIMEOUT" -I wg0 "$target" && success=1 && break
    done
    [ "$success" = "1" ] || exit 1
fi