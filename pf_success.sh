#!/bin/bash

if [ $FIREWALL -eq 1 ]; then
  iptables -A INPUT -p tcp -i wg0 --dport "$1" -j ACCEPT
  iptables -A INPUT -p udp -i wg0 --dport "$1" -j ACCEPT
  echo "$(date): Allowing incoming traffic on port $1"
fi

# Set env var PF_DEST_IP to forward on to another address
# eg PF_DEST_IP=192.168.1.48
if [ -n "$PF_DEST_IP" ]; then
  iptables -t nat -A PREROUTING -p tcp --dport "$1" -j DNAT --to-destination "$PF_DEST_IP:$1"
  iptables -t nat -A PREROUTING -p udp --dport "$1" -j DNAT --to-destination "$PF_DEST_IP:$1"
  echo "$(date): Forwarding incoming VPN traffic on port $1 to $PF_DEST_IP:$1"
fi
