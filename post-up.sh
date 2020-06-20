#!/bin/bash

if [ $LOCAL_NETWORK -eq 1 ]; then
    ip route add $LOCAL_NETWORK via $(ip route show 0.0.0.0/0 dev eth0 | cut -d\  -f3)
fi