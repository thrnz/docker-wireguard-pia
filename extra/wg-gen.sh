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
#  -c </path/to/rsa_4096.crt>   (Optional) Path to PIA ca cert
#                               The request to add the WG pubkey may be insecure if not specified
#  -k </path/to/pubkey.pem>     (Optional) Verify the server list using this public key. Requires OpenSSL.
#  -d <dns server/s>            (Optional) Use these DNS servers in the generated WG config. Defaults to PIA's DNS.
#
# Examples:
#   wg-gen.sh -l swiss -t ~/.token -o ~/wg.conf
#   wg-gen.sh -l swiss -t ~/.token -o ~/wg.conf -c ~/rsa_4096.crt -k ~/pubkey.pem -d 8.8.8.8,8.8.4.4
#
# Available servers can be found here:
#  https://serverlist.piaservers.net/vpninfo/servers/new
# The PIA ca cert can be found here:
#  https://raw.githubusercontent.com/pia-foss/desktop/master/daemon/res/ca/rsa_4096.crt
# The public key for verifying the server list can be found here:
#  https://github.com/pia-foss/desktop/blob/122710c6ada5db83620c63faff2d805ea52d7f40/daemon/src/environment.cpp#L30
#
# Wireguard is not supported outside of the official PIA app at this stage. Use at your own risk!

fatal_error () {
  echo "Fatal error"
  exit 1
}

usage() {
  echo "Options:"
  echo " -t </path/to/tokenfile>      Path to a valid PIA auth token"
  echo " -l <location>                id of the location to connect to (eg. \"swiss\")"
  echo " -o </path/to/wg0.conf        The generated conf will be saved here"
  echo " -c </path/to/rsa_4096.crt>   (Optional) Path to PIA ca cert"
  echo "                              The request to add the WG pubkey may be insecure if not specified"
  echo " -k </path/to/pubkey.pem>     (Optional) Verify the server list using this public key. Requires OpenSSL."
  echo " -d <dns server/s>            (Optional) Use these DNS servers in the generated WG config. Defaults to PIA's DNS."
}

while getopts ":t:l:o:c:k:d:" args; do
  case ${args} in
    t)
      tokenfile=$OPTARG
      ;;
    l)
      location=$OPTARG
      ;;
    o)
      wg_out=$OPTARG
      ;;
    c)
      pia_cacert=$OPTARG
      ;;
    k)
      pia_pubkey=$OPTARG
      ;;
    d)
      dns=$OPTARG
      ;;
  esac
done

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
  serverlist=$(curl --silent --show-error --max-time $curl_max_time \
              "https://serverlist.piaservers.net/vpninfo/servers/new")

  echo "$serverlist" | head -n 1 | tr -d '\n' > $servers_json
  echo "$serverlist" | tail -n +3 | base64 -d > $servers_sig

  [ -n "$pia_pubkey" ] && verify_serverlist

  # Some locations have multiple servers available. Pick a random one.
  totalservers=$(jq -r '.regions | .[] | select(.id=="'$location'") | .servers.wg | length' $servers_json)
  if ! [[ "$totalservers" =~ ^[0-9]+$ ]] || [ $totalservers -eq 0 ] 2>/dev/null; then
    echo "No matching servers found. Valid servers are:"
    jq -r '.regions | .[] | .id' "$servers_json"
    fatal_error
  fi
  serverindex=$(( $RANDOM % $totalservers))
  wg_cn=$(jq -r '.regions | .[] | select(.id=="'$location'") | .servers.wg | .['$serverindex'].cn' $servers_json)
  wg_ip=$(jq -r '.regions | .[] | select(.id=="'$location'") | .servers.wg | .['$serverindex'].ip' $servers_json)
  wg_port=$(jq -r '.groups.wg | .[0] | .ports | .[0]' $servers_json)

  [ $(jq -r '.regions | .[] | select(.id=="'$location'") | .port_forward' $servers_json) == "true" ] && port_forward_avail=1
}

get_wgconf () {
  client_private_key="$(wg genkey)"
  client_public_key=$(wg pubkey <<< "$client_private_key")
  [ $? -ne 0 ] && echo "$(date) Error generating Wireguard key pair" && fatal_error

  # https://github.com/pia-foss/desktop/blob/754080ce15b6e3555321dde2dcfd0c21ec25b1a9/daemon/src/wireguardmethod.cpp#L1150
  if [ -n "$pia_cacert" ]; then
    echo "Registering public key with PIA endpoint $location - $wg_cn ($wg_ip)"
    addkey_response=$(curl --get --silent \
      --data-urlencode "pubkey=$client_public_key" \
      --data-urlencode "pt=$(cat $tokenfile)" \
      --cacert "$pia_cacert" \
      --resolve "$wg_cn:$wg_port:$wg_ip" \
      "https://$wg_cn:$wg_port/addKey")
  else
    echo "(INSECURE) Registering public key with PIA endpoint $location - $wg_cn ($wg_ip)"
    addkey_response=$(curl --get --silent \
      --data-urlencode "pubkey=$client_public_key" \
      --data-urlencode "pt=$(cat $tokenfile)" \
      --insecure \
      "https://$wg_ip:$wg_port/addKey")
  fi
  [ "$(echo $addkey_response | jq -r .status)" != "OK" ] && echo "WG key registration failed" && echo $addkey_response && fatal_error

  peer_ip="$(echo $addkey_response | jq -r .peer_ip)"
  server_public_key="$(echo $addkey_response | jq -r .server_key)"
  server_ip="$(echo $addkey_response | jq -r .server_ip)"
  server_port="$(echo $addkey_response | jq -r .server_port)"

  echo "Generating $wg_out"

  if [ -z "$dns" ]; then
      dns=$(echo $addkey_response | jq -r '.dns_servers[0:2]' | grep ^\  | cut -d\" -f2 | xargs echo | sed -e 's/ /,/g')
      echo "Using PIA DNS servers: $dns"
  else
      echo "Using custom DNS servers: $dns"
  fi

  cat <<CONFF > "$wg_out"
#$wg_cn
[Interface]
PrivateKey = $client_private_key
Address = $peer_ip
DNS = $dns

[Peer]
PublicKey = $server_public_key
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $server_ip:$server_port
CONFF

}

curl_max_time=15
port_forward_avail=0
servers_json="/tmp/servers.json"
servers_sig="/tmp/servers.sig"

# Minimum args needed to run
if [ -z "$tokenfile" ] || [ -z "$location" ] || [ -z "$wg_out" ]; then
   usage && exit 0
fi

get_servers
get_wgconf

[ "$port_forward_avail" -eq 1 ] && echo "Port forwarding is available at this location"

echo "Successfully generated $wg_out"
exit 0