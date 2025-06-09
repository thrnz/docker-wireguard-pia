FROM alpine:latest

RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    grepcidr3 \
    iptables \
    iptables-legacy \
    libcap-utils \
    jq \
    openssl \
    wireguard-go \
    wireguard-tools

# Modify wg-quick so it doesn't die without --privileged
# Set net.ipv4.conf.all.src_valid_mark=1 on container creation using --sysctl if required instead
# To avoid confusion, also suppress the error message that displays even when pre-set to 1 on container creation
RUN sed -i 's/cmd sysctl.*/set +e \&\& sysctl -q net.ipv4.conf.all.src_valid_mark=1 \&> \/dev\/null \&\& set -e/' /usr/bin/wg-quick

# Get the PIA CA cert
ADD https://raw.githubusercontent.com/pia-foss/desktop/master/daemon/res/ca/rsa_4096.crt /rsa_4096.crt

# The PIA desktop app uses this public key to verify server list downloads
# https://github.com/pia-foss/desktop/blob/master/daemon/src/environment.cpp#L30
COPY ./RegionsListPubKey.pem /RegionsListPubKey.pem

# Add main work dir to PATH
WORKDIR /scripts

# Copy scripts to containers
COPY run healthcheck.sh pf_success.sh ./extra/pf.sh ./extra/pia-auth.sh ./extra/wg-gen.sh /scripts/
RUN chmod 755 /scripts/*

# Store persistent PIA stuff here (auth token, server list)
VOLUME /pia

# Store stuff that might be shared with another container here (eg forwarded port)
VOLUME /pia-shared

HEALTHCHECK --interval=1m --timeout=3s --start-period=30s --start-interval=1s --retries=3 \
    CMD /scripts/healthcheck.sh || exit 1

ARG BUILDINFO=manual
ENV BUILDINFO=${BUILDINFO}

CMD ["/scripts/run"]
