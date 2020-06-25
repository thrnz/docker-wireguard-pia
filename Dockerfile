FROM alpine:latest

RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    ip6tables \
    iptables \
    jq \
    wireguard-tools

# Use iptables masquerade NAT rule
ENV IPTABLES_MASQ=1

# Allow traffic to/from the docker network by default
ENV ALLOW_DOCKER=0

ENV LOCAL_NETWORK=

#Don't use PersistentKeepalive by default. 
ENV KEEPALIVE=0

#Use PIA DNS by default. Set this to override.
ENV VPNDNS=

#By default we'll connect to the legacy network. Set this to 1 to use the 'net-gen' network instead.
ENV USEMODERN=0

#Use port forwarding. Requires USEMODERN=1 and a supported server.
ENV PORT_FORWARDING=0

# Get the PIA CA cert
ADD https://raw.githubusercontent.com/pia-foss/desktop/master/daemon/res/ca/rsa_4096.crt /rsa_4096.crt

# Add main work dir to PATH
WORKDIR /scripts

# Copy scripts to containers
COPY pre-up.sh /scripts
COPY post-up.sh /scripts
COPY pre-down.sh /scripts
COPY post-down.sh /scripts
COPY run /scripts
RUN chmod 755 /scripts/*

# Store persistent PIA stuff here (auth token, server list)
VOLUME /pia

# Store stuff that might be shared with another container here (eg forwarded port)
VOLUME /pia-shared

# Normal behavior is just to run wireguard with existing configs
CMD ["/scripts/run"]
