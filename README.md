# docker-wireguard-pia

A Docker container for using Wireguard with PIA.

## Requirements
* The Wireguard kernel module must already be installed on the host.
* An active PIA subscription.

## Config
The following ENV vars are used:
* LOC=swiss

Set this to the desired PIA server (eg. 'us_california'). A complete list can be found [here](https://www.privateinternetaccess.com/vpninfo/servers?version=1001&client=x-alpha).
* USER=p00000000

PIA username
* PASS=xxxxxxxx

PIA password
* ALLOW_DOCKER=0/1

Whether to allow input/output traffic to the Docker network. Set to 1 to enable. Defaults to 0 if not specified.
* LOCAL_NETWORK=192.168.1.0/24

Whether to allow input/output traffic to the LAN. LAN traffic is blocked by default if not specified.
* KEEPALIVE = 25

If defined, PersistentKeepalive will be set to this in the Wireguard config.
* VPNDNS = 8.8.8.8, 8.8.4.4

Use these DNS servers in the Wireguard config. Defaults to PIA's DNS servers if not specified.
* USEMODERN=0/1

Connect to PIA's 'next gen' network. This is required for port forwarding using Wireguard. Defaults to 0 - use legacy network. See [here](https://serverlist.piaservers.net/vpninfo/servers/new) for a list of 'next gen' servers.
* PORT_FORWARDING=0/1

Whether to enable port forwarding. Requires USEMODERN=1 and a supported server. Defaults to 0 if not specified. The forwarded port is dumped to /pia-shared/port.dat for access by other containers.

## Notes
* PIA doesn't support Wireguard connections outside of their official app at this stage (June 2020), so use at your own risk.
* Only tested on a Debian Buster host. May or may not work as expected on other hosts.
* PIA username/password is only used on the first run. An auth token is generated and will be re-used for future runs.
* Persistent data (auth token and server list) is stored in /pia.
* iptables is set to block all non Wireguard traffic by default.
* ipv4 only. All ipv6 traffic should be blocked, but you may want to disable ipv6 on the container anyway.
* An example docker-compose.yml is included.
* Other containers can share the VPN using --net=container or network_mode.

## Credits
Some bits and pieces have been borrowed from the following:
* https://github.com/activeeos/wireguard-docker
* https://github.com/cmulk/wireguard-docker
* https://github.com/dperson/openvpn-client
* https://github.com/pia-foss/desktop
* https://gist.github.com/triffid/da48f3c99f1ff334571ae49be80d591b
