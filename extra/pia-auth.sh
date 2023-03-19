#!/bin/bash

# Generate and output a PIA auth token
#
# Requires jq and curl
#
# Options:
#  -u <username>
#  -p <password>
#
# Example:
#  pia-auth.sh -u myusername -p mypassword > ~/.pia-token
#
# deauth using:
# curl --silent --show-error --request POST \
#        --header "Content-Type: application/json" \
#        --header "Authorization: Token $(cat ~/.pia-token)" \
#        --data "{}" \
#        "https://www.privateinternetaccess.com/api/client/v2/expire_token"

[ -n "$DEBUG" ] && set -o xtrace

while getopts ":u:p:" args; do
  case ${args} in
    u)
      user=$OPTARG
      ;;
    p)
      pass=$OPTARG
      ;;
  esac
done

usage() {
  echo "Options:"
  echo " -u <username>"
  echo " -p <password>"
  exit 1
}

get_auth_token () {
    TOK=$(curl --silent --location --show-error --request POST --max-time "$curl_max_time" \
        'https://www.privateinternetaccess.com/api/client/v2/token' \
        --form "username=$user" \
        --form "password=$pass" | jq -r '.token')
    if [ -z "$TOK" ]; then
      echo "Failed to acquire new auth token" && exit 1
    fi
    echo "$TOK"
}

if [ -z "$pass" ] || [ -z "$user" ]; then
  usage
fi

curl_max_time=15
get_auth_token
exit 0