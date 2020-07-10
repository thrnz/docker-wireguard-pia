FROM alpine:latest

RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    ip6tables \
    iptables \
    jq \
    wireguard-tools

ENV ALLOW_DOCKER=0 \
    LOCAL_NETWORK= \
    KEEPALIVE=0 \
    VPNDNS= \
    USEMODERN=0 \
    PORT_FORWARDING=0 \
    EXIT_ON_FATAL=0

# Get the PIA CA cert
ADD https://raw.githubusercontent.com/pia-foss/desktop/master/daemon/res/ca/rsa_4096.crt /rsa_4096.crt

# Add main work dir to PATH
WORKDIR /scripts

# Copy scripts to containers
COPY pre-up.sh post-up.sh pre-down.sh post-down.sh run /scripts/
RUN chmod 755 /scripts/*

# Store persistent PIA stuff here (auth token, server list)
VOLUME /pia

# Store stuff that might be shared with another container here (eg forwarded port)
VOLUME /pia-shared

# Normal behavior is just to run wireguard with existing configs
CMD ["/scripts/run"]
