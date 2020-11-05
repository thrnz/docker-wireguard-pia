# docker-wireguard-pia

A Docker container for using WireGuard with PIA.

## Requirements
* Ideally the host must already support WireGuard. Pre 5.6 kernels may need to have the module manually installed. If this is not possible, then a userspace implementation can be enabled using the WG_USERSPACE environment variable.
* An active [PIA](https://www.privateinternetaccess.com) subscription.

## Config
The following ENV vars are required:

| ENV Var | Function |
|-------|------|
|```LOC=swiss```|Location id to connect to. Available 'next-gen' server location ids are listed [here](https://serverlist.piaservers.net/vpninfo/servers/new). Example values include ```us_california```, ```ca_ontario```, and ```swiss```. If left empty, or an invalid id is specified, the container will print out all available location ids and exit.
|```USER=p00000000```|PIA username
|```PASS=xxxxxxxx```|PIA password

The rest are optional:

| ENV Var | Function |
|-------|------|
|```LOCAL_NETWORK=192.168.1.0/24```|Whether to route and allow input/output traffic to the LAN. LAN access is blocked by default if not specified. Multiple ranges can be specified, separated by a space.
|```KEEPALIVE=25```|If defined, PersistentKeepalive will be set to this in the WireGuard config.
|```VPNDNS=8.8.8.8, 8.8.4.4```|Use these DNS servers in the WireGuard config. Defaults to PIA's DNS servers if not specified.
|```PORT_FORWARDING=0/1```|Whether to enable port forwarding. Requires a supported server. Defaults to 0 if not specified. The forwarded port number is dumped to ```/pia-shared/port.dat``` for possible access by scripts in other containers.
|```PORT_PERSIST=0/1```|Set to 1 to attempt to keep the same port forwarded when the container is restarted. The port number may persist for up to two months. Defaults to 0 (always acquire a new port number) if not specified.
|```FIREWALL=0/1```|Whether to block non-WireGuard traffic. Defaults to 1 if not specified.
|```EXIT_ON_FATAL=0/1```|There is no error recovery logic at this stage. If something goes wrong we simply go to sleep. By default the container will continue running until manually stopped. Set this to 1 to force the container to exit when an error occurs. Exiting on an error may not be desirable behaviour if other containers are sharing the connection.
|```WG_USERSPACE=0/1```|If the host OS or host Linux kernel does not support WireGuard (certain NAS systems), a userspace implementation ([wireguard-go](https://git.zx2c4.com/wireguard-go/about/)) can be enabled. Defaults to 0 if not specified.

## Notes
* Based on what was found in the source code to the PIA desktop app.
* As of Sep 2020, PIA have released [scripts](https://github.com/pia-foss/manual-connections) for using WireGuard outside of their app.
* Only tested on a Debian Buster host. May or may not work as expected on other hosts.
* PIA username/password is only used on the first run. A persistent auth token is generated and will be re-used for future runs.
* Persistent data is stored in ```/pia```.
* IPv4 only. IPv6 traffic is blocked unless using ```FIREWALL=0``` but you may want to disable IPv6 on the container anyway.
* An example [docker-compose.yml](https://github.com/thrnz/docker-wireguard-pia/blob/master/docker-compose.yml) is included.
* Other containers can share the VPN connection using Docker's [```--net=container:xyz```](https://docs.docker.com/engine/reference/run/#network-settings) or docker-compose's [```network_mode: service:xyz```](https://docs.docker.com/compose/compose-file/#network_mode).
* Standalone [Bash scripts](https://github.com/thrnz/docker-wireguard-pia/tree/master/extra) are available for use outside of Docker.
* The userspace implementation through wireguard-go is very stable but lacks in performance. Looking into supporting ([boringtun](https://github.com/cloudflare/boringtun)) might be beneficial.

## Credits
Some bits and pieces and ideas have been borrowed from the following:
* https://github.com/activeeos/wireguard-docker
* https://github.com/cmulk/wireguard-docker
* https://github.com/dperson/openvpn-client
* https://github.com/pia-foss/desktop
* https://gist.github.com/triffid/da48f3c99f1ff334571ae49be80d591b
* https://stackoverflow.com/a/54595564
* https://github.com/ckulka/docker-multi-arch-example
