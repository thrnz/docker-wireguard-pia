#!/bin/bash

if [ -n "$LOCAL_NETWORK" ]; then
    for range in $LOCAL_NETWORK; do
        echo "$(date): Adding route to $range"
        ip route add $range via $(ip route show 0.0.0.0/0 dev eth0 | cut -d\  -f3)
    done
fi