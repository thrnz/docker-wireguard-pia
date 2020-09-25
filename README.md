# docker-wireguard-pia

A Docker container for using Wireguard with PIA.

## Requirements
* The Wireguard kernel module must already be installed on the host.
* An active [PIA](https://www.privateinternetaccess.com) subscription.

## Config
The following ENV vars are required:

| ENV Var | Function |
|-------|------|
|```LOC=swiss```|Location to connect to. Available 'next-gen' server locations are listed [here](https://serverlist.piaservers.net/vpninfo/servers/new). The 'id' value should be used. Example values include ```us_california```, ```ca_ontario```, and ```swiss```. If left empty, or an invalid location is specified, the container will print out all available locations and exit.
|```USER=p00000000```|PIA username
|```PASS=xxxxxxxx```|PIA password

The rest are optional:

| ENV Var | Function |
|-------|------|
|```LOCAL_NETWORK=192.168.1.0/24```|Whether to route and allow input/output traffic to the LAN. LAN access is blocked by default if not specified. Multiple ranges can be specified, separated by a space.
|```KEEPALIVE=25```|If defined, PersistentKeepalive will be set to this in the Wireguard config.
|```VPNDNS=8.8.8.8, 8.8.4.4```|Use these DNS servers in the Wireguard config. Defaults to PIA's DNS servers if not specified.
|```PORT_FORWARDING=0/1```|Whether to enable port forwarding. Requires a supported server. Defaults to 0 if not specified. The forwarded port number is dumped to ```/pia-shared/port.dat``` for possible access by scripts in other containers.
|```PORT_PERSIST=0/1```|Set to 1 to attempt to keep the same port forwarded when the container is restarted. The port number may persist for up to two months. Defaults to 0 (always acquire a new port number) if not specified.
|```FIREWALL=0/1```|Whether to block non-WireGuard traffic. Defaults to 1 if not specified.
|```EXIT_ON_FATAL=0/1```|There is no error recovery logic at this stage. If something goes wrong we simply go to sleep. By default the container will continue running until manually stopped. Set this to 1 to force the container to exit when an error occurs. Exiting on an error may not be desirable behavior if other containers are sharing the connection.

## Notes
* Based on what was found in the source code to the PIA desktop app.
* As of Sep 2020, PIA have [released](https://github.com/pia-foss/manual-connections) scripts for using Wireguard outside of their app.
* Only tested on a Debian Buster host. May or may not work as expected on other hosts.
* PIA username/password is only used on the first run. A persistent auth token is generated and will be re-used for future runs.
* Persistent data (auth token and server list) is stored in /pia.
* iptables should block all non Wireguard traffic by default.
* ipv4 only. All ipv6 traffic should be blocked, but you may want to disable ipv6 on the container anyway.
* An example [docker-compose.yml](/docker-compose.yml) is included.
* Other containers can share the VPN connection using Docker's [```--net=container:xyz```](https://docs.docker.com/engine/reference/run/#network-settings) or docker-compose's [```network_mode: service:xyz```](https://docs.docker.com/compose/compose-file/#network_mode).
* Standalone [Bash scripts](/extra) are available for use outside of Docker.

## Credits
Some bits and pieces and ideas have been borrowed from the following:
* https://github.com/activeeos/wireguard-docker
* https://github.com/cmulk/wireguard-docker
* https://github.com/dperson/openvpn-client
* https://github.com/pia-foss/desktop
* https://gist.github.com/triffid/da48f3c99f1ff334571ae49be80d591b
