#!/bin/bash

# Bash script for port-forwarding on the PIA 'next-gen' network.
#
# Requires jq and curl.
#
# Options:
#  -t </path/to/tokenfile>      Path to a valid PIA auth token
#  -i <pf api ip>               (Optional) IP to send port-forward API requests to.
#                               An 'educated guess' is made if not specified.
#  -n <vpn common name>         (Optional) Common name of the VPN server (eg. "london411")
#                               An 'educated guess' is made if not specified.
#  -p </path/to/port.dat>       (Optional) Dump forwarded port here for access by other scripts
#  -f <interface name>          (Optional) Network interface to use for requests
#  -s </path/to/script.sh>      (Optional) Run a script on success.
#                               The forwarded port is passed as an argument.
#
# Examples:
#   pf.sh -t ~/.pia-token
#   pf.sh -t ~/.pia-token -n sydney402
#   pf.sh -t ~/.pia-token -i 10.13.14.1 -n london416 -p /port.dat -f wg0
#
# For port forwarding on the next-gen network, we need a valid PIA auth token (see pia-auth.sh) and to know the address to send API requests to.
#
# With Wireguard, the PIA app uses the 'server_vip' address found in the 'addKey' response (eg 10.x.x.1), although 'server_ip' also appears to work.
# With OpenVPN, the PIA app uses the gateway IP (also 10.x.x.1)
#
# Optionally, if we know the common name of the server we're connected to we can verify our HTTPS requests.
#
# Port forwarding appears to involve two api calls. The first (getSignature) is done once on startup and again when the returned pf 'token' will soon expire.
# Port forwarding tokens seem to last ~2 months, so the chances of needing to call it again are low but we may as well do what the app does.
# The second (bindPort) is done once at startup and again every 15 mins to 'keep the forwarded port alive'.
#
# This script has been tested with Wireguard and briefly with OpenVPN
#
# This script is based on what was found in the source code to their desktop app (v.2.2.0):
# https://github.com/pia-foss/desktop/blob/2.2.0/daemon/src/portforwardrequest.cpp
# Use at your own risk!
#
# As of Sep 2020, PIA have released their own standalone scripts for use outside of their app:
# https://github.com/pia-foss/manual-connections
#
# Feel free to take apart and use in your own projects. A link back to the original might be nice though.

# An error with no recovery logic occured
fatal_error () {
  cleanup
  echo "$(date): Fatal error"
  exit 1
}

cleanup(){
  [ "$cacert_istemp" == "1" ] && [ -w "$cacert" ] && rm "$cacert"
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
                              An 'educated guess' is made if not specified.
 -n <vpn common name>         (Optional) Common name of the VPN server (eg. \"london411\")
                              An 'educated guess' is made if not specified.
 -p </path/to/port.dat>       (Optional) Dump forwarded port here for access by other scripts
 -f <interface name>          (Optional) Network interface to use for requests
 -s </path/to/script.sh>      (Optional) Run a script on success.
                              The forwarded port is passed as an argument."
}

while getopts ":t:i:n:c:p:f:s:r:" args; do
  case ${args} in
    t)
      tokenfile=$OPTARG
      ;;
    i)
      api_ip=$OPTARG
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
    f)
      iface_tr="-i $OPTARG"
      iface_curl="--interface $OPTARG"
      ;;
    s)
      post_script=$OPTARG
      ;;
    r)
      persist_file=$OPTARG
      ;;
  esac
done

bind_port () {
  pf_bind=$(curl --get --silent --show-error $iface_curl \
      --retry $curl_retry --retry-delay $curl_retry_delay --max-time $curl_max_time \
      --data-urlencode "payload=$pf_payload" \
      --data-urlencode "signature=$pf_getsignature" \
      $verify \
      "https://$pf_host:19999/bindPort")
  if [ "$(echo $pf_bind | jq -r .status)" != "OK" ]; then
    echo "$(date): bindPort error"
    echo "$pf_bind"
    return 1
  fi
  return 0
}

get_sig () {
  # Attempt to reuse our previous port if requested
  if [ -n "$persist_file" ] && [ -r "$persist_file" ]; then
    echo "$(date) Reusing previous PF token"
    pf_getsig=$(cat "$persist_file")
  else
    pf_getsig=$(curl --get --silent --show-error $iface_curl \
      --retry $curl_retry --retry-delay $curl_retry_delay --max-time $curl_max_time \
      --data-urlencode "token=$(cat $tokenfile)" \
      $verify \
      "https://$pf_host:19999/getSignature")
  fi
  if [ "$(echo $pf_getsig | jq -r .status)" != "OK" ]; then
    echo "$(date): getSignature error"
    echo "$pf_getsig"
    fatal_error
  fi
  # Save response for re-use if requested
  [ -n "$persist_file" ] && echo "$pf_getsig" > "$persist_file"
  pf_payload=$(echo $pf_getsig | jq -r .payload)
  pf_getsignature=$(echo $pf_getsig | jq -r .signature)
  pf_port=$(echo $pf_payload | base64 -d | jq -r .port)
  pf_token_expiry_raw=$(echo $pf_payload | base64 -d | jq -r .expires_at)
  # Coreutils date doesn't need format specified (-D), whereas BusyBox does
  if date --help 2>&1 /dev/null | grep -iq 'busybox'; then
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
# This seems to work for both Wireguard and OpenVPN.
# Ideally we'd have been provided a cn, in case we 'guess' the wrong IP.
# Must be a better way to do this.
if [ -z "$api_ip" ]; then
  api_ip=$(traceroute -4 -m 1 $iface_tr privateinternetaccess.com | tail -n 1 | awk '{print $2}')
  # Very basic sanity check - make sure it matches 10.x.x.1
  if ! echo "$api_ip" | grep -q '10\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.1'; then
    echo "$(date): Automatically getting API IP failed."
    fatal_error
  fi
  echo "$(date): Using $api_ip as API endpoint"
fi

# If we haven't been passed a cn, then use the cn the server is claiming
if [ -z "$vpn_cn" ]; then
  possible_cn=$(curl $iface_curl --insecure --verbose --head https://$api_ip:19999 2>&1 | grep '\\*  subject' | sed 's/.*CN=\(.*\)\;.*/\1/')
  # Sanity check - match 'lowercase123'
  if echo "$possible_cn" | grep -q '[a-z]*[0-9]\{3\}'; then
    echo "$(date): Using $possible_cn as cn"
    vpn_cn="$possible_cn"
  fi
fi

# If we've been provided a cn, we can verify using the PIA ca cert
if [ -n "$vpn_cn" ]; then
  # Get the PIA ca crt if we weren't given it
  if [ -z "$cacert" ]; then
    echo "$(date): Getting PIA ca cert"
    cacert=$(mktemp)
    cacert_istemp=1
    if ! curl $iface_curl --get --silent --max-time "$curl_max_time" --output "$cacert" \
      --retry $curl_retry --retry-delay $curl_retry_delay --max-time $curl_max_time \
      "https://raw.githubusercontent.com/pia-foss/desktop/master/daemon/res/ca/rsa_4096.crt"; then
      echo "(date): Failed to download PIA ca cert"
      fatal_error
    fi
  fi
  verify="--cacert $cacert --resolve $vpn_cn:19999:$api_ip"
  pf_host="$vpn_cn"
  echo "$(date): Verifying API requests. CN: $vpn_cn"
else
  # For simplicity, use '--insecure' by default, though show a warning
  echo "$(date): API requests may be insecure. Specify a common name using -n."
  verify="--insecure"
  pf_host="$api_ip"
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
    if ! bind_port; then
      # If we attempted to use a previous port and binding failed then discard it and retry
      if [ -n "$persist_file" ] && [ -w "$persist_file" ]; then
        echo "$(date): Discarding previous PF token and trying again"
        rm "$persist_file"
        get_sig
        bind_port || fatal_error
      else
        fatal_error
      fi
    fi
    echo "$(date): Obtained PF token. Expires at $pf_token_expiry_raw"
    echo "$(date): Server accepted PF bind"
    echo "$(date): Forwarding on port $pf_port"
    # Run another script if requested
    [ -n "$post_script" ] && echo "$(date): Running $post_script" && eval "$post_script $pf_port"
    echo "$(date): Rebind interval: $pf_bindinterval seconds"
    # Dump port here if requested
    [ -n "$portfile" ] && echo "$(date): Port dumped to $portfile" && echo $pf_port > "$portfile"
    echo "$(date): This script should remain running to keep the forwarded port alive"
    echo "$(date): Press Ctrl+C to exit"
  fi
  sleep $pf_bindinterval &
  wait $!
  bind_port || fatal_error
done

