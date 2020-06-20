#!/bin/bash

if [ ! -z $LOCAL_NETWORK ]; then
    ip route del $LOCAL_NETWORK via $(ip route show 0.0.0.0/0 dev eth0 | cut -d\  -f3)
fi