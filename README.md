# docker-wireguard-pia

A Docker container for using WireGuard with PIA.

## Requirements
* Ideally the host must already support WireGuard. Pre 5.6 kernels may need to have the module manually installed. `wg-quick` should automatically fall back to a userspace implementation (`wireguard-go`) if the kernel module is missing, however the container may need access to the `/dev/net/tun` device for this to work.
* An active [PIA](https://www.privateinternetaccess.com) subscription.

## Config
The following ENV vars are required:

| ENV Var | Function |
|-------|------|
|```LOC=swiss```|Location id to connect to. Available server location ids are listed [here](https://serverlist.piaservers.net/vpninfo/servers/v6). Example values include ```us_california```, ```ca_ontario```, and ```swiss```. If left empty the container will print out all currently available location ids and exit. <br />Multiple ids can be listed, separated by either a space or a comma, and are used as fallback if the initial endpoint registration fails.
|```USER=xxxxxxxx```|PIA username
|```PASS=xxxxxxxx```|PIA password

The rest are optional:

| ENV Var | Function |
|-------|------|
|```LOCAL_NETWORK=192.168.1.0/24```|Whether to route and allow input/output traffic to the LAN. LAN access is blocked by default if not specified. Multiple ranges can be specified, separated by a comma or space. Note that there may be DNS issues if this overlaps with PIA's default DNS servers (`10.0.0.243` and `10.0.0.242` as of July 2022). Custom DNS servers can be defined using `VPNDNS` (see below) if this is an issue.
|```KEEPALIVE=25```|If defined, PersistentKeepalive will be set to this in the WireGuard config.
|```MTU=1420```|This can be used to override ```wg-quick```'s automatic MTU setting on the Wireguard interface if needed. By default this remains unset (ie. let ```wg-quick``` choose).
|```VPNDNS=8.8.8.8, 8.8.4.4```|Use these DNS servers in the WireGuard config. PIA's DNS servers will be used if not specified. Use 0 to disable making any changes to the default container DNS settings. (Note: Using any DNS servers other than PIA's may lead to DNS queries being leaked outside the VPN connection.)
|```PORT_FORWARDING=0/1```|Whether to enable port forwarding. Requires a supported server. Defaults to 0 if not specified.
|```PORT_FILE=/pia-shared/port.dat```|The forwarded port number is dumped here for possible access by scripts in other containers. By default this is ```/pia-shared/port.dat```.
|```PORT_FILE_CLEANUP=0/1```|Remove the file containing the forwarded port number on exit. Defaults to 0 if not specified.
|```PORT_PERSIST=0/1```|Set to 1 to attempt to keep the same port forwarded when the container is restarted. The port number may persist for up to two months. Defaults to 0 (always acquire a new port number) if not specified.
|```PORT_SCRIPT=/path/to/script.sh```|A mounted custom script can be run inside the container once a port is successfully forwarded if needed. The forwarded port number is passed as the first command line argument. By default this remains unset. See [issue #26](https://github.com/thrnz/docker-wireguard-pia/issues/26) for more info.
|```FIREWALL=0/1```|Whether to block non-WireGuard traffic. Defaults to 1 if not specified.
|```EXIT_ON_FATAL=0/1```|There is no error recovery logic at this stage. If something goes wrong we simply go to sleep. By default the container will continue running until manually stopped. Set this to 1 to force the container to exit when an error occurs. Exiting on an error may not be desirable behaviour if other containers are sharing the connection.
|```USER_FILE=/run/secrets/pia-username``` ```PASS_FILE=/run/secrets/pia-password```|PIA credentials can also be read in from existing files (eg for use with Docker secrets)
|```PIA_IP=x.x.x.x``` ```PIA_CN=hostname401``` ```PIA_PORT=1337```|Connect to a specific server by manually setting all three of these. This will override whatever ```LOC``` is set to.
|```FWD_IFACE``` ```PF_DEST_IP```|If needed, the container can be used as a gateway for other containers or devices by setting these. See [issue #20](https://github.com/thrnz/docker-wireguard-pia/issues/20) for more info. Note that these are for a specific use case, and in many cases using Docker's ```--net=container:xyz``` or docker-compose's ```network_mode: service:xyz``` instead, and leaving these vars unset, would be an easier way of accessing the VPN and forwarded port from other containers.
|```NFTABLES=0/1```|Alpine uses `iptables-legacy` by defualt. If needed, `iptables-nft` can be used instead by setting this to 1. Defaults to 0 if not specified. See [issue #37](https://github.com/thrnz/docker-wireguard-pia/issues/37).
|`PRE_UP` `POST_UP` `PRE_DOWN` `POST_DOWN`|Custom commands and/or scripts can be run at certain stages if needed. See [below](#scripting) for more info.
|`PIA_DIP_TOKEN`|A dedicated ip token can be used by setting this. When set, `LOC` is not used.

## Scripting
Custom commands and/or scripts can be run at certain stages of the container's life-cycle by setting the `PRE_UP`, `POST_UP`, `PRE_DOWN`, and `POST_DOWN` env vars. `PRE_UP` is run prior to generating the WireGuard config, `POST_UP` is run after the WireGuard interface is brought up, and `PRE_DOWN` and `POST_DOWN` are run before and after the interface is brought down again when the container exits.

In addition, scripts mounted in `/pia/scripts` named `pre-up.sh`, `post-up.sh`, `pre-down.sh` and `post-down.sh` will be run at the appropriate stage if present. See [issue #33](https://github.com/thrnz/docker-wireguard-pia/issues/33) for more info.

## Notes
* Based on what was found in the source code to the PIA desktop app.
* As of Sep 2020, PIA have released [scripts](https://github.com/pia-foss/manual-connections) for using WireGuard outside of their app.
* Only tested on a Debian Buster host. May or may not work as expected on other hosts.
* PIA username/password is only used on the first run. A persistent auth token is generated and will be re-used for future runs.
* Persistent data is stored in ```/pia```.
* IPv4 only. IPv6 traffic is blocked unless using ```FIREWALL=0``` but you may want to disable IPv6 on the container anyway.
* An example [docker-compose.yml](https://github.com/thrnz/docker-wireguard-pia/blob/master/docker-compose.yml) is included. Some more working examples can be found [here](https://github.com/thrnz/docker-wireguard-pia/wiki/Examples).
* Other containers can share the VPN connection using Docker's [```--net=container:xyz```](https://docs.docker.com/engine/reference/run/#network-settings) or docker-compose's [```network_mode: service:xyz```](https://github.com/compose-spec/compose-spec/blob/master/spec.md#network_mode).
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
