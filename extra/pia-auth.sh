#!/bin/bash

# Generate and output a PIA auth token
#
# Requires jq and curl
#
# Options:
#  -u <username>
#  -p <password>
#  -i <meta server ip>          (Optional)
#  -o <meta server port>        (Optional)
#  -n <meta server cn>          (Optional)
#  -c <cacert path>             (Optional) Path to ca cert used to secure communication with "meta" servers
#
# Examples:
#  ./pia-auth.sh -u myusername -p mypassword > ~/.pia-token
#  ./pia-auth.sh -u myusername -p mypassword -i 12.34.56.78 -n location401 -p 443 -c /path/to/ca.crt > ~/.pia-token
#
# By default, the www.privateinternetaccess.com API endpoint is used.
# If needed, 'meta' services on the VPN servers themselves can be used instead.
#
# deauth using:
# curl --silent --show-error --request POST \
#        --header "Content-Type: application/json" \
#        --header "Authorization: Token $(cat ~/.pia-token)" \
#        --data "{}" \
#        "https://www.privateinternetaccess.com/api/client/v2/expire_token"

[ -n "$DEBUG" ] && set -o xtrace

while getopts ":u:p:i:c:o:n:" args; do
  case ${args} in
    u)
      user="$OPTARG"
      ;;
    p)
      pass="$OPTARG"
      ;;
    i)
      meta_ip="$OPTARG"
      ;;
    c)
      cacert="$OPTARG"
      ;;
    o)
      meta_port="$OPTARG"
      ;;
    n)
      meta_cn="$OPTARG"
      ;;
  esac
done

usage() {
  echo 'Options:
  -u <username>
  -p <password>
  -i <meta-server ip>          (Optional)
  -o <meta-server port>        (Optional)
  -n <meta-server cn>          (Optional)
  -c <cacert path>             (Optional) Path to ca cert used to secure communication with "meta" servers'
  exit 1
}

get_auth_token () {
  if [ -n "$meta_port" ] && [ -n "$meta_ip" ] && [ -n "$meta_cn" ] && [ -n "$cacert" ]; then
    # https://github.com/pia-foss/desktop/blob/master/daemon/src/metaserviceapibase.h
    token_response=$(curl --silent --location --show-error --request POST --max-time "$curl_max_time" \
        --resolve "$meta_cn:$meta_port:$meta_ip" \
        --data-urlencode "username=$user" \
        --data-urlencode "password=$pass" \
        --cacert "$cacert" \
        "https://$meta_cn:$meta_port/api/client/v2/token")
  else
    token_response=$(curl --silent --location --show-error --request POST --max-time "$curl_max_time" \
        'https://www.privateinternetaccess.com/api/client/v2/token' \
        --data-urlencode "username=$user" \
        --data-urlencode "password=$pass")
  fi
  TOK=$(jq -r .'token' <<< "$token_response")
  if [ -z "$TOK" ] || [ "$TOK" == "null" ]; then
    echo "Failed to acquire new auth token. Response:" >&2
    echo "$token_response" >&2
    exit 1
  fi
  echo "$TOK"
}

if [ -z "$pass" ] || [ -z "$user" ]; then
  usage
fi

curl_max_time=15
get_auth_token
exit 0