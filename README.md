# docker-wireguard-pia

A Docker container for using Wireguard with PIA.

## Requirements
* The Wireguard kernel module must already be installed on the host.
* An active [PIA](https://www.privateinternetaccess.com) subscription.

## Config
The following ENV vars are used:

| ENV Var | Function |
|-------|------|
|LOC=swiss|Location of the server to connect to. Available classic/legacy locations are listed [here](https://www.privateinternetaccess.com/vpninfo/servers?version=1001&client=x-alpha) and available 'next-gen' servers are listed [here](https://serverlist.piaservers.net/vpninfo/servers/new). For classic/legacy locations, LOC should be set to the location's index value, and for 'next-gen' servers the 'id' value should be used. Example values include ```us_california```, ```ca_ontario```, and ```swiss```. If left empty, or an invalid location is specified, the container will print out all available locations for the selected infrastructure and exit.
|USEMODERN=0/1| Set this to 1 if you want to use the '[next gen](https://www.privateinternetaccess.com/blog/private-internet-access-next-generation-network-now-available-for-beta-preview/)' network. Otherwise the classic/legacy network will be used. This must be set to 1 for ```PORT_FORWARDING``` to function.
|USER=p00000000|PIA username
|PASS=xxxxxxxx|PIA password
|ALLOW_DOCKER=0/1|Whether to allow input/output traffic to the Docker network. Set to 1 to enable. Defaults to 0 if not specified.
|LOCAL_NETWORK=192.168.1.0/24|Whether to allow input/output traffic to the LAN. LAN traffic is blocked by default if not specified.
|KEEPALIVE = 25|If defined, PersistentKeepalive will be set to this in the Wireguard config.
|VPNDNS = 8.8.8.8, 8.8.4.4|Use these DNS servers in the Wireguard config. Defaults to PIA's DNS servers if not specified.
|PORT_FORWARDING=0/1|Whether to enable port forwarding. Requires ```USEMODERN=1``` and a supported server. Defaults to 0 if not specified. The forwarded port number is dumped to ```/pia-shared/port.dat``` for possible access by scripts in other containers.
|EXIT_ON_FATAL=0|There is no error recovery logic at this stage. If something goes wrong we simply go to sleep. By default the container will continue running until manually stopped. Set this is set to 1 to force the container to exit when an error occurs. Exiting on an error may not be desirable behavior if other containers are sharing the conneciton.

## Notes
* PIA doesn't support Wireguard connections outside of their official app at this stage (June 2020), so use at your own risk. YMMV.
* Only tested on a Debian Buster host. May or may not work as expected on other hosts.
* PIA username/password is only used on the first run. A persistent auth token is generated and will be re-used for future runs.
* Persistent data (auth token and server list) is stored in /pia.
* iptables should block all non Wireguard traffic by default.
* ipv4 only. All ipv6 traffic should be blocked, but you may want to disable ipv6 on the container anyway.
* An example docker-compose.yml is included.
* Other containers can share the VPN using --net=container or docker-compose's network_mode.

## Credits
Some bits and pieces have been borrowed from the following:
* https://github.com/activeeos/wireguard-docker
* https://github.com/cmulk/wireguard-docker
* https://github.com/dperson/openvpn-client
* https://github.com/pia-foss/desktop
* https://gist.github.com/triffid/da48f3c99f1ff334571ae49be80d591b
