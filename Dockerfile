FROM alpine:3.24

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
    patch \
    sed \
    tini \
    wireguard-go \
    wireguard-tools

# wg-quick patches:
# - don't fail attempting to modify src_valid_mark without --privileged
# - Add ALLOW_MISSING_IPTABLES_RULES env var
ADD ./patches/wg-quick.diff /tmp/wg-quick.diff
RUN patch /usr/bin/wg-quick < /tmp/wg-quick.diff && \
	rm /tmp/wg-quick.diff

ADD https://raw.githubusercontent.com/pia-foss/desktop/master/daemon/res/ca/rsa_4096.crt /rsa_4096.crt

# The PIA desktop app uses this public key to verify server list downloads
# https://github.com/pia-foss/desktop/blob/master/daemon/src/environment.cpp#L30
COPY ./RegionsListPubKey.pem /RegionsListPubKey.pem

WORKDIR /scripts

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

ENTRYPOINT ["/sbin/tini", "--"]

CMD ["/scripts/run"]
