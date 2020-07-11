#!/bin/bash

if [ -n "$LOCAL_NETWORK" ]; then
    echo "$(date): Removing route to $LOCAL_NETWORK"
    ip route del $LOCAL_NETWORK via $(ip route show 0.0.0.0/0 dev eth0 | cut -d\  -f3)
fi