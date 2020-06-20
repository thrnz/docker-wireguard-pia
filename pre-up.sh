#!/bin/bash

#Drop everything by default
ip6tables -P OUTPUT DROP &> /dev/null
ip6tables -P INPUT DROP &> /dev/null
ip6tables -P FORWARD DROP &> /dev/null
iptables -P OUTPUT DROP > /dev/null
iptables -P INPUT DROP > /dev/null
iptables -P FORWARD DROP > /dev/null

iptables -F OUTPUT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

iptables -F INPUT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT

#Allow some local stuff
#WG stuff is allowed in PostUp

#Set env var ALLOW_DOCKER=1 to allow docker network input/output
if [ $ALLOW_DOCKER -eq 1 ] ; then 
    docker_network="$(ip -o addr show dev eth0|
            awk '$3 == "inet" {print $4}')"

    iptables -A OUTPUT -o eth0 --destination $docker_network -j ACCEPT
    iptables -A INPUT -i eth0 --source $docker_network -j ACCEPT
fi

#Set env var LOCAL_NETWORK=192.168.1.1/24 to allow LAN input/output
if [ $LOCAL_NETWORK -eq 1 ]; then
    iptables -A OUTPUT -o eth0 --destination $LOCAL_NETWORK -j ACCEPT
    iptables -A INPUT -i eth0 --source $LOCAL_NETWORK -j ACCEPT
fi

exit 0