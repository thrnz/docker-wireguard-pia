#!/bin/bash

# Bash script for port-forwarding on the PIA 'next-gen' network.
#
# Requires jq and curl.
#
# Options:
#  -t </path/to/tokenfile>      Path to a valid PIA auth token
#  -i <pf api ip>               IP to send port-forward API requests to
#                               For Wireguard, this is the VPN server IP (ie. Endpoint in wg.conf)
#                               For OpenVPN, this is the VPN interface gateway IP (eg 10.x.x.1)
#  -n <vpn common name>         (Optional) Common name of the VPN server (eg. "london411")
#                               Requests will be insecure if not specified
#  -c </path/to/rsa_4096.crt>   (Optional) Path to PIA ca cert
#                               Requests will be insecure if not specified
#  -p </path/to/port.dat>       (Optional) Dump forwarded port here for access by other scripts
#
# Examples:
#   pf.sh -t ~/.pia-token -i 37.235.97.81
#   pf.sh -t ~/.pia-token -i 37.235.97.81 -n london416 -c /rsa_4096.crt -p /port.dat
#
# For port forwarding on the next-gen network, we need a valid PIA auth token and to know the address to send API requests to.
# Optionally, if we know the common name of the server we're connected to we can verify our HTTPS requests.
# The PIA ca cert can be found here: https://raw.githubusercontent.com/pia-foss/desktop/master/daemon/res/ca/rsa_4096.crt
#
# Previously, PIA port forwarding was done with a single request when the VPN came up.
# Now we need to 'rebind' every 15 mins in order to keep the port open/alive.
#
# This script has been tested with Wireguard and briefly with OpenVPN
#
# Port forwarding on the 'next-gen' network isn't supported outside of the official PIA app at this stage. Use at your own risk!
#
# Based on what was found in the open source app:
# https://github.com/pia-foss/desktop/blob/master/daemon/src/portforwardrequest.cpp

# An error with no recovery logic occured
fatal_error () {
  echo "$(date): Fatal error"
  exit 1
}

# Handle shutdown behavior
finish () {
  echo "$(date): Port forward rebinding stopped. The port will likely close soon."
  exit 0
}
trap finish SIGTERM SIGINT SIGQUIT

usage() {
  echo "Options:"
  echo " -t </path/to/tokenfile>      Path of a valid PIA auth token"
  echo " -i <pf api ip>               IP to send port-forward API requests to"
  echo "                              For Wireguard, this is the VPN server IP (ie. Endpoint in wg.conf)"
  echo "                              For OpenVPN, this is the VPN interface gateway IP (eg 10.x.x.1)"
  echo " -n <vpn common name>         (Optional) Common name of the VPN server (eg. \"london411\")"
  echo "                              Requests will be insecure if not specified"
  echo " -c </path/to/rsa_4096.crt>   (Optional) Path to PIA ca cert"
  echo "                              Requests will be insecure if not specified"
  echo " -p </path/to/port.dat>       (Optional) Dump forwarded port here for access by other scripts"
}

while getopts ":t:i:n:c:p:" args; do
  case ${args} in
    t)
      tokenfile=$OPTARG
      ;;
    i)
      vpn_ip=$OPTARG
      ;;
    n)
      vpn_cn=$OPTARG
      ;;
    c)
      cacert=$OPTARG
      ;;
    p)
      portfile=$OPTARG
      ;;
  esac
done

bind_port () {
  pf_bind=$(curl --get --silent --show-error \
      --retry 5 --retry-delay 15 --max-time $curl_max_time \
      --data-urlencode "payload=$pf_payload" \
      --data-urlencode "signature=$pf_getsignature" \
      $verify \
      "https://$pf_host:19999/bindPort")
  if [ "$(echo $pf_bind | jq -r .status)" != "OK" ]; then
    echo "$(date): bindPort error"
    echo $pf_bind
    fatal_error
  fi
}

get_sig () {
  pf_getsig=$(curl --get --silent --show-error \
    --retry 5 --retry-delay 15 --max-time $curl_max_time \
    --data-urlencode "token=$(cat $tokenfile)" \
    $verify \
    "https://$pf_host:19999/getSignature")
  if [ "$(echo $pf_getsig | jq -r .status)" != "OK" ]; then
    echo "$(date): getSignature error"
    echo $pf_getsig
    fatal_error
  fi
  pf_payload=$(echo $pf_getsig | jq -r .payload)
  pf_getsignature=$(echo $pf_getsig | jq -r .signature)
  pf_port=$(echo $pf_payload | base64 -d | jq -r .port)
  pf_token_expiry_raw=$(echo $pf_payload | base64 -d | jq -r .expires_at)
  # Coreutils date doesn't need format specified (-D), whereas BusyBox does
  if date --help 2>&1 /dev/null | grep -i 'busybox'; then
    pf_token_expiry=$(date -D %Y-%m-%dT%H:%M:%S --date="$pf_token_expiry_raw" +%s)
  else
    pf_token_expiry=$(date --date="$pf_token_expiry_raw" +%s)
  fi
}

curl_max_time=15

# Rebind every 15 mins (same as desktop app)
pf_bindinterval=$(( 15 * 60))
# Get a new token when the current one has less than this remaining
# Defaults to 7 days (same as desktop app)
pf_minreuse=$(( 60 * 60 * 24 * 7 ))

pf_remaining=0
pf_firstrun=1

# Minimum args needed to run
if [ -z "$tokenfile" ] || [ -z "$vpn_ip" ]; then
  usage && exit 0
fi

# For simplicity, use '--insecure' by default.
# To properly mimic what the desktop app does, supply a cn and a cacert
verify="--insecure"
pf_host="$vpn_ip"
[ -n "$cacert" ] && [ -n "$vpn_cn" ] &&
  verify="--cacert $cacert --resolve $vpn_cn:19999:$vpn_ip" &&
  pf_host="$vpn_cn" &&
  echo "$(date): Verifying requests to $vpn_cn using $cacert"

# Main loop
while true; do
  pf_remaining=$((  $pf_token_expiry - $(date +%s) ))
  # Get a new pf token as the previous one will expire soon
  if [ $pf_remaining -lt $pf_minreuse ]; then
    if [ $pf_firstrun -ne 1 ]; then
      echo "$(date): PF token will expire soon. Getting new one."
    else
      echo "$(date): Getting PF token"
      pf_firstrun=0
    fi
    get_sig
    echo "$(date): Obtained PF token. Expires at $pf_token_expiry_raw"
    bind_port
    echo "$(date): Server accepted PF bind"
    echo "$(date): Forwarding on port $pf_port"
    echo "$(date): Rebind interval: $pf_bindinterval seconds"
    # Dump port here if requested
    [ -n "$portfile" ] && echo "$(date): Port dumped to $portfile" && echo $pf_port > "$portfile"
  fi
  sleep $pf_bindinterval &
  wait $!
  bind_port
done

