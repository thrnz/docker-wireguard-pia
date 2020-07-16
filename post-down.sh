#!/bin/bash

iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

#Set env var ALLOW_DOCKER=1 to allow docker network input/output
if [ $ALLOW_DOCKER -eq 1 ] ; then 
    docker_network="$(ip -o addr show dev eth0|
            awk '$3 == "inet" {print $4}')"
    echo "$(date): Revoking network access to $docker_network (docker)"
    iptables -D OUTPUT -o eth0 --destination $docker_network -j ACCEPT
    iptables -D INPUT -i eth0 --source $docker_network -j ACCEPT
fi

#Set env var LOCAL_NETWORK=192.168.1.1/24 to allow LAN input/output
if [ -n "$LOCAL_NETWORK" ]; then
   for range in $LOCAL_NETWORK; do
        echo "$(date): Revoking network access to $range"
        iptables -D OUTPUT -o eth0 --destination $range -j ACCEPT
        iptables -D INPUT -i eth0 --source $range -j ACCEPT
    done
fi