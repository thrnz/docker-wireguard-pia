#!/bin/bash

if [ -n "$LOCAL_NETWORK" ]; then
    echo "$(date): Adding route to $LOCAL_NETWORK"
    ip route add $LOCAL_NETWORK via $(ip route show 0.0.0.0/0 dev eth0 | cut -d\  -f3)
fi