#!/bin/bash

# Bash script for generating basic Wireguard config files (for use with wg-quick) for the PIA 'next-gen' network
#
# Requires Wireguard (for generating a key pair), jq and curl
# Optionally requires OpenSSL for verifying server list
#
# Options:
#  -t </path/to/tokenfile>      Path to a valid PIA auth token
#  -l <location>                id of the location to connect to (eg. "swiss")
#  -o </path/to/wg0.conf        The generated .conf will be saved here
#  -k </path/to/pubkey.pem>     (Optional) Verify the server list using this public key. Requires OpenSSL.
#  -d <dns server/s>            (Optional) Use these DNS servers in the generated WG config. Defaults to PIA's DNS.
#  -m <mtu>                     (Optional) Use this as the interface's mtu value in the generated config
#  -c </path/to/ca.crt>         (Optional) Path to PIA ca cert. Fetched from the PIA Github repository if not provided.
#  -a                           List available locations and whether they support port forwarding
#
# Examples:
#   wg-gen.sh -a
#   wg-gen.sh -l swiss -t ~/.token -o ~/wg.conf
#   wg-gen.sh -l swiss -t ~/.token -o ~/wg.conf -k ~/pubkey.pem -d 8.8.8.8,8.8.4.4
#
# To force the use of a specific server, the PIA_IP PIA_PORT and PIA_CN env vars must all be set
# eg: $ PIA_IP=1.2.3.4 PIA_PORT=1337 PIA_CN=hostname401 wg-gen.sh -t ~/.token -o ~/wg.conf
#
# To use a dedicated ip, the PIA_DIP_TOKEN env var must be set
# eg: $ PIA_DIP_TOKEN=DIPabc123 wg-gen.sh -t ~/.token -o ~/wg.conf
#
# API requests can be sent via PIA's 'meta' servers by setting the META_IP META_CN and META_PORT env vars
# eg: $ META_IP=123.45.67.89 META_CN=hostname401 META_PORT=443 ./wg-gen.sh -t ~/.token ~/wg.conf
#
# Available servers can be found here:
#  https://serverlist.piaservers.net/vpninfo/servers/v6
# The public key for verifying the server list can be found here:
#  https://github.com/pia-foss/desktop/blob/122710c6ada5db83620c63faff2d805ea52d7f40/daemon/src/environment.cpp#L30
# The PIA ca cert can be found here:
#  https://github.com/pia-foss/desktop/blob/master/daemon/res/ca/rsa_4096.crt
#
# As of Sep 2020, PIA have released their own standalone scripts for use outside of their app:
# https://github.com/pia-foss/manual-connections

# Exit codes:
# 0: Success
# 1: Anything else
# 2: Auth error
# 3: Invalid server location
# 4: Registration failed

[ -n "$DEBUG" ] && set -o xtrace

fatal_error () {
  cleanup
  [ -n "$1" ] && exit "$1"
  exit 1
}

cleanup(){
  [ -w "$servers_raw" ] && rm "$servers_raw"
  [ -w "$servers_json" ] && rm "$servers_json"
  [ -w "$servers_sig" ] && rm "$servers_sig"
  [ -w "$addkey_response" ] && rm "$addkey_response"
  [ -w "$pia_cacert_tmp" ] && rm "$pia_cacert_tmp"
  return 0
}

usage() {
  echo "Options:"
  echo " -t </path/to/tokenfile>      Path to a valid PIA auth token"
  echo " -l <location>                id of the location to connect to (eg. \"swiss\")"
  echo " -o </path/to/wg0.conf        The generated conf will be saved here"
  echo " -k </path/to/pubkey.pem>     (Optional) Verify the server list using this public key. Requires OpenSSL."
  echo " -d <dns server/s>            (Optional) Use these DNS servers in the generated WG config. Defaults to PIA's DNS."
  echo " -m <mtu>                     (Optional) Use this as the interface's mtu value in the generated config"
  echo " -c </path/to/ca.crt>         (Optional) Path to PIA ca cert. Fetched from the PIA Github repository if not provided."
  echo " -a                           List available locations and whether they support port forwarding"
}

parse_args() {
  while getopts ":t:l:o:k:c:d:m:a" args; do
    case ${args} in
      t)
        tokenfile="$OPTARG"
        ;;
      l)
        location="$OPTARG"
        ;;
      o)
        wg_out="$OPTARG"
        ;;
      k)
        pia_pubkey="$OPTARG"
        ;;
      c)
        pia_cacert="$OPTARG"
        ;;
      d)
        dns="$OPTARG"
        ;;
      m)
        mtu="$OPTARG"
        ;;
      a)
        list_and_exit=1
        ;;
    esac
  done
}

# The PIA desktop app uses a public key to verify server list downloads.
# https://github.com/pia-foss/desktop/blob/b701601bfa806621a41039514bbb507e250466ec/common/src/jsonrefresher.cpp#L93
verify_serverlist ()
{
  if openssl dgst -sha256 -verify "$pia_pubkey" -signature "$servers_sig" "$servers_json"; then
    echo "Verified server list"
  else
    echo "Failed to verify server list"
    fatal_error
  fi
}

get_dip_serverinfo ()
{
  if [ -n "$META_IP" ] && [ -n "$META_CN" ] && [ -n "$META_PORT" ]; then
    echo "$(date): Fetching dedicated ip server info via meta server: ip: $META_IP, cn: $META_CN, port: $META_PORT"
    dip_response=$(curl --silent --show-error $curl_params --location --request POST \
    "https://$META_CN:$META_PORT/api/client/v2/dedicated_ip" \
    --header 'Content-Type: application/json' \
    --header "Authorization: Token $(cat $tokenfile)" \
    --cacert "$pia_cacert" --resolve "$META_CN:$META_PORT:$META_IP" \
    --data-raw '{
      "tokens":["'"$PIA_DIP_TOKEN"'"]
    }')
  else
    echo "$(date): Fetching dedicated ip server info"
    dip_response=$(curl --silent --show-error $curl_params --location --request POST \
    'https://www.privateinternetaccess.com/api/client/v2/dedicated_ip' \
    --header 'Content-Type: application/json' \
    --header "Authorization: Token $(cat $tokenfile)" \
    --data-raw '{
      "tokens":["'"$PIA_DIP_TOKEN"'"]
    }')
  fi

  [ "$dip_response" == "HTTP Token: Access denied." ] && echo "Auth failed" && fatal_error 2

  if [ "$(jq -r '.[0].status' <<< "$dip_response")" != "active" ]; then
    echo "$(date): Failed to fetch dedicated ip server info. Response:"
    echo "$dip_response"
    fatal_error
  fi

  wg_port=1337
  wg_cn=$(jq -r '.[0].cn' <<< "$dip_response")
  wg_ip=$(jq -r '.[0].ip' <<< "$dip_response")

  echo "$(date): Dedicated ip: $wg_ip, cn: $wg_cn"

  # PIA's standalone scripts seem to assume port forwarding is available everywhere apart from the us
  [[ $(jq -r '.[0].id' <<< "$dip_response") != us_* ]] && port_forward_avail=1
}

get_servers() {
  if [ -n "$META_IP" ] && [ -n "$META_CN" ] && [ -n "$META_PORT" ]; then
    echo "Fetching next-gen PIA server list via meta server: ip: $META_IP, cn: $META_CN, port: $META_PORT"
    curl --silent --show-error $curl_params --cacert "$pia_cacert" --resolve "$META_CN:$META_PORT:$META_IP" \
      "https://$META_CN:$META_PORT/vpninfo/servers/v6" > "$servers_raw"
  else
    echo "Fetching next-gen PIA server list"
    curl --silent --show-error $curl_params \
      "https://serverlist.piaservers.net/vpninfo/servers/v6" > "$servers_raw"
  fi
  head -n 1 "$servers_raw" | tr -d '\n' > "$servers_json"
  tail -n +3 "$servers_raw" | base64 -d > "$servers_sig"
  [ -n "$pia_pubkey" ] && verify_serverlist

  [ "$list_and_exit" -eq 1 ] && echo "Available location ids:" && jq '.regions | .[] | {name, id, port_forward}' "$servers_json" && cleanup && exit 0

  # Some locations have multiple servers available. Pick a random one.
  totalservers=$(jq -r '.regions | .[] | select(.id=="'$location'") | .servers.wg | length' "$servers_json")
  if ! [[ "$totalservers" =~ ^[0-9]+$ ]] || [ "$totalservers" -eq 0 ] 2>/dev/null; then
    echo "Location \"$location\" not found. Run with -a to list valid servers."
    fatal_error 3
  fi
  serverindex=$(( RANDOM % totalservers))
  wg_cn=$(jq -r '.regions | .[] | select(.id=="'$location'") | .servers.wg | .['$serverindex'].cn' "$servers_json")
  wg_ip=$(jq -r '.regions | .[] | select(.id=="'$location'") | .servers.wg | .['$serverindex'].ip' "$servers_json")
  wg_port=$(jq -r '.groups.wg | .[0] | .ports | .[0]' "$servers_json")

  [ $(jq -r '.regions | .[] | select(.id=="'$location'") | .port_forward' "$servers_json") == "true" ] && port_forward_avail=1
}

get_wgconf () {
  client_private_key="$(wg genkey)"
  if ! client_public_key=$(wg pubkey <<< "$client_private_key"); then
    echo "$(date) Error generating Wireguard key pair" && fatal_error
  fi

  # https://github.com/pia-foss/desktop/blob/754080ce15b6e3555321dde2dcfd0c21ec25b1a9/daemon/src/wireguardmethod.cpp#L1150

  if [ -z "$pia_cacert" ]; then
    echo "$(date) Fetching PIA ca cert"
    pia_cacert_tmp=$(mktemp)
    if ! curl --get --silent --show-error $curl_params --output "$pia_cacert_tmp" "https://raw.githubusercontent.com/pia-foss/desktop/master/daemon/res/ca/rsa_4096.crt"; then
      echo "Failed to download PIA ca cert"
      fatal_error
    fi
    pia_cacert="$pia_cacert_tmp"
  fi

  if [ -n "$PIA_DIP_TOKEN" ]; then
    echo "Registering public key with PIA dedicated ip endpoint; cn: $wg_cn, ip: $wg_ip"
    curl --get --silent --show-error $curl_params \
      --user "dedicated_ip_$PIA_DIP_TOKEN:$wg_ip" \
      --data-urlencode "pubkey=$client_public_key" \
      --cacert "$pia_cacert" \
      --resolve "$wg_cn:$wg_port:$wg_ip" \
      "https://$wg_cn:$wg_port/addKey" > "$addkey_response"
  else
    echo "Registering public key with PIA endpoint; id: $location, cn: $wg_cn, ip: $wg_ip"
    curl --get --silent --show-error $curl_params \
      --data-urlencode "pubkey=$client_public_key" \
      --data-urlencode "pt=$(cat $tokenfile)" \
      --cacert "$pia_cacert" \
      --resolve "$wg_cn:$wg_port:$wg_ip" \
      "https://$wg_cn:$wg_port/addKey" > "$addkey_response"
  fi

  [ "$(jq -r .status "$addkey_response")" == "ERROR" ] && [ "$(jq -r .message "$addkey_response")" == "Login failed!" ] && echo "Auth failed" && cat "$addkey_response" && fatal_error 2
  [ "$(jq -r .status "$addkey_response")" != "OK" ] && echo "WG key registration failed" && cat "$addkey_response" && fatal_error 4

  peer_ip="$(jq -r .peer_ip "$addkey_response")"
  server_public_key="$(jq -r .server_key "$addkey_response")"
  server_port="$(jq -r .server_port "$addkey_response")"
  pfapi_ip="$(jq -r .server_vip "$addkey_response")"

  echo "Generating $wg_out"

  if [ -z "$dns" ]; then
      dns=$(jq -r '.dns_servers[0:2]' "$addkey_response" | grep ^\  | cut -d\" -f2 | xargs echo | sed -e 's/ /,/g')
      echo "Using PIA DNS servers: $dns"
  elif [ "$dns" = "0" ]; then
      echo "Using default container DNS servers"
      dns=""
  else
      echo "Using custom DNS servers: $dns"
  fi

  cat <<CONFF > "$wg_out"
#cn: $wg_cn
#pf api ip: $pfapi_ip
[Interface]
PrivateKey = $client_private_key
Address = $peer_ip
DNS = $dns
CONFF

  if [ -n "$mtu" ]; then
	echo "Using custom MTU: $mtu"
	echo "MTU = $mtu" >> "$wg_out"
  fi

  cat <<CONFF >> "$wg_out"

[Peer]
PublicKey = $server_public_key
AllowedIPs = 0.0.0.0/0
Endpoint = $wg_ip:$server_port
CONFF

}

curl_params="--retry 5 --retry-delay 5 --max-time 120 --connect-timeout 15"

port_forward_avail=0
list_and_exit=0

parse_args "$@"

# Minimum args needed to run
if [ "$list_and_exit" -eq 0 ]; then
  if [ -z "$tokenfile" ] || [ -z "$wg_out" ]; then
    usage && exit 0
  fi
fi

servers_raw=$(mktemp)
servers_sig=$(mktemp)
servers_json=$(mktemp)
addkey_response=$(mktemp)

if [ -n "$PIA_DIP_TOKEN" ]; then
  get_dip_serverinfo
# Set env vars PIA_CN, PIA_IP and PIA_PORT to connect to a specific server
elif [ -n "$PIA_CN" ] && [ -n "$PIA_IP" ] && [ -n "$PIA_PORT" ]; then
  wg_cn="$PIA_CN"
  wg_ip="$PIA_IP"
  wg_port="$PIA_PORT"
  location="manual"
else
  # Otherwise get what we need from the server list
  get_servers
fi

get_wgconf

if [ "$port_forward_avail" -eq 1 ]; then
  echo "Port forwarding is available at this location"
else
  echo "Port forwarding is not available at this location"
fi

echo "Successfully generated $wg_out"

cleanup
exit 0