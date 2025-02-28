# docker-wireguard-pia

A Docker container for using WireGuard with PIA.

## Requirements
* Ideally the host should already support WireGuard. Pre 5.6 kernels may need to have the module manually installed. `wg-quick` should automatically fall back to a userspace implementation (`wireguard-go`) if needed, however the container may need access to the `/dev/net/tun` device for this to work.
* The container requires the `NET_ADMIN` [capability](https://docs.docker.com/compose/compose-file/05-services/#cap_add). `SYS_MODULE` may also be needed in some cases, especially when WireGuard support is provided via kernel module.
* An active [PIA](https://www.privateinternetaccess.com) subscription.

## Examples
An example [docker-compose.yml](https://github.com/thrnz/docker-wireguard-pia/blob/master/docker-compose.yml) is available. Some more working examples can be found [here](https://github.com/thrnz/docker-wireguard-pia/wiki/Examples).

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
|```LOCAL_NETWORK=192.168.1.0/24```|Whether to route and allow input/output traffic to the LAN. LAN access will be unavailable if not specified. Multiple ranges can be specified, separated by a comma or space. Note that there may be DNS issues if this overlaps with PIA's default DNS servers (`10.0.0.243` and `10.0.0.242` as of July 2022). Custom DNS servers can be defined using `VPNDNS` (see below) if this is an issue.
|```KEEPALIVE=25```|If defined, PersistentKeepalive will be set to this in the WireGuard config. This can be used to ensure incoming packets on an idle link aren't lost when behind NAT. The [WireGuard QuickStart guide](https://www.wireguard.com/quickstart/) suggests a value of 25 if needed. By default this remains unset.
|```MTU=1420```|This can be used to override ```wg-quick```'s automatic MTU setting on the Wireguard interface if needed. By default this remains unset (ie. let ```wg-quick``` choose).
|```VPNDNS=8.8.8.8, 8.8.4.4```|Use these DNS servers in the WireGuard config. PIA's DNS servers will be used if not specified. Use 0 to disable making any changes to the default container DNS settings. (Note: Using any DNS servers other than PIA's may lead to DNS queries being leaked outside the VPN connection.)
|```PORT_FORWARDING=0/1```|Whether to enable port forwarding. Requires a supported server. Defaults to 0 if not specified.
|```PORT_FILE=/pia-shared/port.dat```|The forwarded port number is dumped here for possible access by scripts in other containers. By default this is ```/pia-shared/port.dat```.
|```PORT_FILE_CLEANUP=0/1```|Remove the file containing the forwarded port number on exit. Defaults to 0 if not specified.
|```PORT_PERSIST=0/1```|Set to 1 to attempt to keep the same port forwarded when the container is restarted. The port number may persist for up to two months. Defaults to 0 (always acquire a new port number) if not specified.
|`PORT_FATAL=0/1`|Whether to consider port forwarding errors as fatal or not. May be useful when combined with `EXIT_ON_FATAL` if needed. Defaults to 0 if not specified.
|```PORT_SCRIPT=/path/to/script.sh```|A mounted custom script can be run inside the container once a port is successfully forwarded if needed. The forwarded port number is passed as the first command line argument. By default this remains unset. See [issue #26](https://github.com/thrnz/docker-wireguard-pia/issues/26) for more info.
|```FIREWALL=0/1```|Whether to block non-WireGuard traffic. Defaults to 1 if not specified.
|```EXIT_ON_FATAL=0/1```|By default the container will continue running until manually stopped. Set this to 1 to force the container to exit when an error occurs. Exiting on an error may not be desirable behaviour if other containers are sharing the connection.
|```FATAL_SCRIPT=/path/to/script.sh```|A mounted custom script can be run inside the container if a fatal error occurs. By default this remains unset.
|```USER_FILE=/run/secrets/pia-username``` ```PASS_FILE=/run/secrets/pia-password```|PIA credentials can also be read in from existing files (eg for use with Docker secrets)
|```PIA_IP=x.x.x.x``` ```PIA_CN=hostname401``` ```PIA_PORT=1337```|Connect to a specific server by manually setting all three of these. This will override whatever ```LOC``` is set to.
|```FWD_IFACE``` ```PF_DEST_IP```|If needed, the container can be used as a gateway for other containers or devices by setting these. See [issue #20](https://github.com/thrnz/docker-wireguard-pia/issues/20) for more info. Note that these are for a specific use case, and in many cases using Docker's ```--net=container:xyz``` or docker-compose's ```network_mode: service:xyz``` instead, and leaving these vars unset, would be an easier way of accessing the VPN and forwarded port from other containers.
|`PRE_UP` `POST_UP` `PRE_DOWN` `POST_DOWN` `PRE_RECONNECT` `POST_RECONNECT`|Custom commands and/or scripts can be run at certain stages if needed. See [below](#scripting) for more info.
|`PIA_DIP_TOKEN`|A dedicated ip token can be used by setting this. When set, `LOC` is not used.
|`META_IP=x.x.x.x` `META_CN=hostname401` `META_PORT=443`|On startup, the container needs untunnelled access to PIA's API in order to download the server list and to generate a persistent auth token if needed. Optionally, PIA's 'meta' servers (found in PIA's [server list](https://serverlist.piaservers.net/vpninfo/servers/v6)) can be used instead of the default API endpoints by setting `META_IP` and `META_CN`. These can be set to a different location than `LOC`. `META_PORT` is optional and defaults to 443, although 8080 also appears to be available. See [issue #109](https://github.com/thrnz/docker-wireguard-pia/issues/109) for more info.
|`ACTIVE_HEALTHCHECKS=0/1`|The container contains a very basic Docker [healthcheck](https://docs.docker.com/reference/dockerfile/#healthcheck) script that can be used to ensure the VPN is up before starting other services. By default only passive checks that don't generate any traffic are run. Set this to 1 to also allow checks that generate traffic, such as `ping`, in order to detect if the remote endpoint is responding.
|`HEALTHCHECK_PING_TARGET`|When active healthchecks are enabled or reconnect logic is used, this can be used to override the target/s that gets pinged when testing that the endpoint is still responding. Defaults to `www.privateinternetaccess.com`. Can be set to space or comma separated list of multiple targets, in which case all need to fail for the endpoint to be considered unresponsive.
|`HEALTHCHECK_PING_TIMEOUT`|Can be used to override the number of seconds to wait for a reply when pinging a target. Defaults to 3.
`NFTABLES=0/1`|Alpine uses the `nf_tables` iptables backend by default. The container should automatically fall back to the legacy backend if needed. Set this to `0` to force the use of the legacy backend, or to `1` to force the use of the `nf_tables` backend if desired.
`RECONNECT=0/1`|The container can optionally attempt to detect and recover from an unresponsive endpoint. This is done without the WireGuard interface being brought down. `HEALTHCHECK_PING_TARGET` can be used to set the target used to detect if the remote endpoint is responding. Defaults to 0 if not specified.
`MONITOR_INTERVAL=60` `MONITOR_RETRIES=3`|These are used by the `RECONNECT` logic, and can be used to tweak the probe frequency and the number of retries made before considering an endpoint unresponsive.

## Scripting
Custom commands and/or scripts can be run at certain stages of the container's life-cycle by setting the `PRE_UP`, `POST_UP`, `PRE_DOWN`, `POST_DOWN`, `PRE_RECONNECT`, and `POST_RECONNECT` env vars. `PRE_UP` is run prior to generating the WireGuard config, `POST_UP` is run after the WireGuard interface is brought up, `PRE_DOWN` and `POST_DOWN` are run before and after the interface is brought down again when the container exits, and `PRE_RECONNECT` and `POST_RECONNECT` are run before and after an attempt is made to reconnect after an unresponsive endpoint is detected (assuming `RECONNECT=1` is set).

In addition, scripts mounted in `/pia/scripts` named `pre-up.sh`, `post-up.sh`, `pre-down.sh` and `post-down.sh` will be run at the appropriate stage if present. See [issue #33](https://github.com/thrnz/docker-wireguard-pia/issues/33) for more info.

## Networking
To keep things simple, network setup is mostly handled by `wg-quick`. All traffic is routed down the WireGuard tunnel, with exceptions added for any ranges manually defined by `LOCAL_NETWORK`. Note that `LOCAL_NETWORK` must be set correctly if LAN access is needed.

Firewall rules are added dropping all traffic by default, and only encrypted/tunneled traffic, attached Docker network traffic, and `LOCAL_NETWORK` traffic is explicitly allowed. This can be disabled by setting the `FIREWALL=0` env var if desired.

Other containers can access the VPN connection using Docker's [`--net=container:xyz`](https://docs.docker.com/engine/network/#container-networks) or docker-compose's [`network_mode: service:xyz`](https://docs.docker.com/reference/compose-file/services/#network_mode). Note that network related settings for other containers (such as exposing ports) need to be set on the VPN container itself. When the VPN container is brought down or recreated, Docker appears to bring down the shared network with it, so other containers may also require recreating to regain network access.

The container doesn't support IPv6. Any IPv6 traffic is dropped unless using `FIREWALL=0`, though it might be worth disabling IPv6 on container creation anyway.

WireGuard keys seem to expire at PIA's end after several hours of inactivity. Setting the `KEEPALIVE` env var may be enough to prevent this from happening if needed.

The container has optional recovery logic if the remote endpoint permanently stops responding. If an unresponsive endpoint is detected, an attempt is made to generate a new WireGuard config and, if successful, is applied to the interface without needing to bring it down. The port forwarding script is then restarted if needed.

## Notes
* WireGuard config generation and port forwarding was based on what was found in the source code to the PIA desktop app. The standalone [Bash scripts](https://github.com/thrnz/docker-wireguard-pia/tree/master/extra) used by the container are available for use outside of Docker.
* As of Sep 2020, PIA have released their own [scripts](https://github.com/pia-foss/manual-connections) for using WireGuard and port forwarding outside of their app.
* Persistent data is stored in ```/pia```.
* If strict reverse path filtering is used, then the `net.ipv4.conf.all.src_valid_mark=1` sysctl should be set on container creation to prevent incoming packets being dropped. See [issue #96](https://github.com/thrnz/docker-wireguard-pia/issues/96) for more info.
* The userspace implementation through wireguard-go is very stable but lacks in performance. Looking into supporting ([boringtun](https://github.com/cloudflare/boringtun)) might be beneficial.
* Container images are available on both Docker Hub (`thrnz/docker-wireguard-pia`) and GitHub's Container Registry (`ghcr.io/thrnz/docker-wireguard-pia`). Images are rebuilt monthly to keep Alpine packages up to date.

## Credits
Some bits and pieces and ideas have been borrowed from the following:
* https://github.com/activeeos/wireguard-docker
* https://github.com/cmulk/wireguard-docker
* https://github.com/dperson/openvpn-client
* https://github.com/pia-foss/desktop
* https://gist.github.com/triffid/da48f3c99f1ff334571ae49be80d591b
