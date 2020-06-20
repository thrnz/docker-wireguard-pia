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

# Add main work dir to PATH
WORKDIR /scripts

# Copy scripts to containers
COPY pre-up.sh /scripts
COPY post-up.sh /scripts
COPY pre-down.sh /scripts
COPY run /scripts
RUN chmod 755 /scripts/*

# Get the PIA CA cert
ADD https://raw.githubusercontent.com/pia-foss/desktop/master/daemon/res/ca/rsa_4096.crt /rsa_4096.crt

# Store persistent PIA stuff here (auth token, server list)
VOLUME /pia

# Normal behavior is just to run wireguard with existing configs
CMD ["/scripts/run"]
