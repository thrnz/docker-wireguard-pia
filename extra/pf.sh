#!/bin/bash

# Bash script for port-forwarding on the PIA 'next-gen' network.
#
# Requires jq and curl.
#
# Options:
#  -t </path/to/tokenfile>      Path to a valid PIA auth token
#  -i <pf api ip>               (Optional) IP to send port-forward API requests to.
#                               The PIA app sends requests to the gateway IP (eg 10.x.x.1),
#                               however for Wireguard the server IP also seems to work.
#                               An 'educated guess' is made if not specified.
#  -n <vpn common name>         (Optional) Common name of the VPN server (eg. "london411")
#                               Requests will be insecure if not specified
#  -p </path/to/port.dat>       (Optional) Dump forwarded port here for access by other scripts
#
# Examples:
#   pf.sh -t ~/.pia-token
#   pf.sh -t ~/.pia-token -n sydney402
#   pf.sh -t ~/.pia-token -i 10.13.14.1 -n london416 -p /port.dat
#
# For port forwarding on the next-gen network, we need a valid PIA auth token (see pia-auth.sh) and to know the address to send API requests to.
#
# Optionally, if we know the common name of the server we're connected to we can verify our HTTPS requests.
#
# Previously, PIA port forwarding was done with a single request when the VPN came up.
# Now we need to 'rebind' every 15 mins in order to keep the port open/alive.
#
# This script has been tested with Wireguard and briefly with OpenVPN
#
# PIA haven't provided steps for port forwarding on the 'next-gen' network outside of the official app at this stage (Aug 2020).
# This script is based on what was found in the source code to their desktop app (v.2.2.0):
# https://github.com/pia-foss/desktop/blob/2.2.0/daemon/src/portforwardrequest.cpp
# Use at your own risk!

# An error with no recovery logic occured
fatal_error () {
  cleanup
  echo "$(date): Fatal error"
  exit 1
}

cleanup(){
  [ -w "$cacert" ] && rm "$cacert"
}

# Handle shutdown behavior
finish () {
  cleanup
  echo "$(date): Port forward rebinding stopped. The port will likely close soon."
  exit 0
}
trap finish SIGTERM SIGINT SIGQUIT

usage() {
  echo "Options:
 -t </path/to/tokenfile>      Path to a valid PIA auth token
 -i <pf api ip>               (Optional) IP to send port-forward API requests to.
                              The PIA app sends requests to the gateway IP (eg 10.x.x.1),
                              however for Wireguard the server IP also works.
                              An 'educated guess' is made if not specified.
 -n <vpn common name>         (Optional) Common name of the VPN server (eg. \"london411\")
                              Requests will be insecure if not specified
 -p </path/to/port.dat>       (Optional) Dump forwarded port here for access by other scripts"
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
    p)
      portfile=$OPTARG
      ;;
  esac
done

bind_port () {
  pf_bind=$(curl --get --silent --show-error \
      --retry $curl_retry --retry-delay $curl_retry_delay --max-time $curl_max_time \
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
    --retry $curl_retry --retry-delay $curl_retry_delay --max-time $curl_max_time \
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
  if date --help 2>&1 /dev/null | grep -i 'busybox' > /dev/null; then
    pf_token_expiry=$(date -D %Y-%m-%dT%H:%M:%S --date="$pf_token_expiry_raw" +%s)
  else
    pf_token_expiry=$(date --date="$pf_token_expiry_raw" +%s)
  fi
}

# We don't use any error handling or retry logic beyond what curl provides
curl_max_time=15
curl_retry=5
curl_retry_delay=15

# Rebind every 15 mins (same as desktop app)
pf_bindinterval=$(( 15 * 60))
# Get a new token when the current one has less than this remaining
# Defaults to 7 days (same as desktop app)
pf_minreuse=$(( 60 * 60 * 24 * 7 ))

pf_remaining=0
pf_firstrun=1

# Minimum args needed to run
if [ -z "$tokenfile" ]; then
  usage && exit 0
fi

# Hacky way to try to automatically get the API IP: use the first hop of a traceroute.
# We can't just get the default gateway from 'ip route' as wg-quick doesn't replace the default route.
# Ideally we'd have been provided a cn, in case we 'guess' the wrong IP.
# Must be a better way to do this.
if [ -z "$vpn_ip" ]; then
  vpn_ip=$(traceroute -4 -m 1 privateinternetaccess.com | tail -n 1 | awk '{print $2}')
  # Very basic sanity check - make sure it matches 10.x.x.1
  if ! echo "$vpn_ip" | grep '10\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.1' > /dev/null; then
    echo "$(date): Automatically getting API IP failed."
    fatal_error
  fi
  echo "$(date): Using $vpn_ip as API endpoint"
fi

# If we've been provided a cn, we can verify using the PIA ca cert
if [ -n "$vpn_cn" ]; then
  cacert=$(mktemp)
  if ! curl --get --silent --max-time "$curl_max_time" --output "$cacert" "https://raw.githubusercontent.com/pia-foss/desktop/master/daemon/res/ca/rsa_4096.crt"; then
    echo "(date): Failed to download PIA ca cert"
    fatal_error
  fi
  verify="--cacert $cacert --resolve $vpn_cn:19999:$vpn_ip"
  pf_host="$vpn_cn"
  echo "$(date): Verifying API requests. CN: $vpn_cn"
else
  # For simplicity, use '--insecure' by default, though show a warning
  echo "$(date): API requests may be insecure. Specify a common name using -n."
  verify="--insecure"
  pf_host="$vpn_ip"
fi

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

