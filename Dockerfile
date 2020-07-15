FROM alpine:latest

RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    ip6tables \
    iptables \
    jq \
    openssl \
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

# The PIA desktop app uses this public key to verify server list downloads
# https://github.com/pia-foss/desktop/blob/master/daemon/src/environment.cpp#L30
COPY ./RegionsListPubKey.pem /RegionsListPubKey.pem

# Add main work dir to PATH
WORKDIR /scripts

# Copy scripts to containers
COPY pre-up.sh post-up.sh pre-down.sh post-down.sh run /scripts/
RUN chmod 755 /scripts/*

# Store persistent PIA stuff here (auth token, server list)
VOLUME /pia

# Store stuff that might be shared with another container here (eg forwarded port)
VOLUME /pia-shared

CMD ["/scripts/run"]
