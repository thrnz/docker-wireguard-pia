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
#  -a                           List available locations and whether they support port forwarding
#
# Examples:
#   wg-gen.sh -a
#   wg-gen.sh -l swiss -t ~/.token -o ~/wg.conf
#   wg-gen.sh -l swiss -t ~/.token -o ~/wg.conf -k ~/pubkey.pem -d 8.8.8.8,8.8.4.4
#
# Available servers can be found here:
#  https://serverlist.piaservers.net/vpninfo/servers/new
# The public key for verifying the server list can be found here:
#  https://github.com/pia-foss/desktop/blob/122710c6ada5db83620c63faff2d805ea52d7f40/daemon/src/environment.cpp#L30
#
# As of Sep 2020, PIA have released their own standalone scripts for use outside of their app:
# https://github.com/pia-foss/manual-connections

# Exit codes:
# 0: Success
# 1: Anything else
# 2: Auth error
# 3: Invalid server location

fatal_error () {
  cleanup
  [ -n "$1" ] && exit $1
  exit 1
}

cleanup(){
  [ -w "$servers_raw" ] && rm "$servers_raw"
  [ -w "$servers_json" ] && rm "$servers_json"
  [ -w "$servers_sig" ] && rm "$servers_sig"
  [ -w "$addkey_response" ] && rm "$addkey_response"
  [ -w "$pia_cacert" ] && rm "$pia_cacert"
}

usage() {
  echo "Options:"
  echo " -t </path/to/tokenfile>      Path to a valid PIA auth token"
  echo " -l <location>                id of the location to connect to (eg. \"swiss\")"
  echo " -o </path/to/wg0.conf        The generated conf will be saved here"
  echo " -k </path/to/pubkey.pem>     (Optional) Verify the server list using this public key. Requires OpenSSL."
  echo " -d <dns server/s>            (Optional) Use these DNS servers in the generated WG config. Defaults to PIA's DNS."
  echo " -a                           List available locations and whether they support port forwarding"
}

parse_args() {
  while getopts ":t:l:o:k:d:a" args; do
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
      c)
        pia_cacert="$OPTARG"
        ;;
      k)
        pia_pubkey="$OPTARG"
        ;;
      d)
        dns="$OPTARG"
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

get_servers() {
  echo "Fetching next-gen PIA server list"
  curl --silent --show-error --max-time "$curl_max_time" \
              "https://serverlist.piaservers.net/vpninfo/servers/new" > "$servers_raw"
  head -n 1 "$servers_raw" | tr -d '\n' > "$servers_json"
  tail -n +3 "$servers_raw" | base64 -d > "$servers_sig"
  [ -n "$pia_pubkey" ] && verify_serverlist

  [ "$list_and_exit" -eq 1 ] && echo "Available location ids:" && jq '.regions | .[] | {id, port_forward}' "$servers_json" && cleanup && exit 0

  # Some locations have multiple servers available. Pick a random one.
  totalservers=$(jq -r '.regions | .[] | select(.id=="'$location'") | .servers.wg | length' "$servers_json")
  if ! [[ "$totalservers" =~ ^[0-9]+$ ]] || [ "$totalservers" -eq 0 ] 2>/dev/null; then
    echo "Location \"$location\" not found. Run with -a to list valid servers."
    fatal_error 3
  fi
  serverindex=$(( $RANDOM % $totalservers))
  wg_cn=$(jq -r '.regions | .[] | select(.id=="'$location'") | .servers.wg | .['$serverindex'].cn' "$servers_json")
  wg_ip=$(jq -r '.regions | .[] | select(.id=="'$location'") | .servers.wg | .['$serverindex'].ip' "$servers_json")
  wg_port=$(jq -r '.groups.wg | .[0] | .ports | .[0]' "$servers_json")

  [ $(jq -r '.regions | .[] | select(.id=="'$location'") | .port_forward' "$servers_json") == "true" ] && port_forward_avail=1
}

get_wgconf () {
  client_private_key="$(wg genkey)"
  client_public_key=$(wg pubkey <<< "$client_private_key")
  [ $? -ne 0 ] && echo "$(date) Error generating Wireguard key pair" && fatal_error

  # https://github.com/pia-foss/desktop/blob/754080ce15b6e3555321dde2dcfd0c21ec25b1a9/daemon/src/wireguardmethod.cpp#L1150

  if ! curl --get --silent --max-time "$curl_max_time" --output "$pia_cacert" "https://raw.githubusercontent.com/pia-foss/desktop/master/daemon/res/ca/rsa_4096.crt"; then
    echo "Failed to download PIA ca cert"
    fatal_error
  fi

  echo "Registering public key with PIA endpoint; id: $location, cn: $wg_cn, ip: $wg_ip"
  curl --get --silent \
    --data-urlencode "pubkey=$client_public_key" \
    --data-urlencode "pt=$(cat $tokenfile)" \
    --cacert "$pia_cacert" \
    --resolve "$wg_cn:$wg_port:$wg_ip" \
    "https://$wg_cn:$wg_port/addKey" > "$addkey_response"

  [ "$(jq -r .status "$addkey_response")" == "ERROR" ] && [ "$(jq -r .message "$addkey_response")" == "Login failed!" ] && echo "Auth failed" && fatal_error 2
  [ "$(jq -r .status "$addkey_response")" != "OK" ] && echo "WG key registration failed" && cat "$addkey_response" && fatal_error

  peer_ip="$(jq -r .peer_ip "$addkey_response")"
  server_public_key="$(jq -r .server_key "$addkey_response")"
  server_ip="$(jq -r .server_ip "$addkey_response")"
  server_port="$(jq -r .server_port "$addkey_response")"
  pfapi_ip="$(jq -r .server_vip "$addkey_response")"

  echo "Generating $wg_out"

  if [ -z "$dns" ]; then
      dns=$(jq -r '.dns_servers[0:2]' "$addkey_response" | grep ^\  | cut -d\" -f2 | xargs echo | sed -e 's/ /,/g')
      echo "Using PIA DNS servers: $dns"
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

[Peer]
PublicKey = $server_public_key
AllowedIPs = 0.0.0.0/0
Endpoint = $server_ip:$server_port
CONFF

}

curl_max_time=15
port_forward_avail=0
list_and_exit=0

parse_args "$@"

# Minimum args needed to run
if [ "$list_and_exit" -eq 0 ]; then
  if [ -z "$tokenfile" ] || [ -z "$location" ] || [ -z "$wg_out" ]; then
    usage && exit 0
  fi
fi

servers_raw=$(mktemp)
servers_sig=$(mktemp)
servers_json=$(mktemp)
addkey_response=$(mktemp)
pia_cacert=$(mktemp)


get_servers
get_wgconf

[ "$port_forward_avail" -eq 1 ] && echo "Port forwarding is available at this location"

echo "Successfully generated $wg_out"

cleanup
exit 0