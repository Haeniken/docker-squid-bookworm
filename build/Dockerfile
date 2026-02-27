FROM debian:bookworm-slim
LABEL maintainer="me@haeniken.com.com"

ENV SQUID_VERSION=5.7-2+deb12u5 \
    SQUID_CACHE_DIR=/var/spool/squid \
    SQUID_USER=proxy

# Single hardening/setup layer:
# - install only required packages (no recommends)
# - patch stock squid.conf to include conf.d
# - create runtime dirs with strict permissions
# - add minimal placeholder conf so include/*.conf always resolves in image
# - remove apt cache/lists and docs/man/info/locale payload to reduce image size and attack surface
RUN set -eux; \
  apt-get update; \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    squid-openssl=${SQUID_VERSION} \
    ca-certificates; \
  \
  # Patch distro squid.conf:
  # 1) un-comment default localnet allow rule template
  # 2) ensure conf.d include exists so custom ACL/log/perf files are loaded
  # 3) disable default daemon access_log (we configure stdio logs via conf.d)
  sed '/^#http_access allow localnet/s/^#//' -i /etc/squid/squid.conf; \
  grep -q '^include /etc/squid/conf.d/\*' /etc/squid/squid.conf \
    || sed '/^# INSERT YOUR OWN RULE(S) HERE TO ALLOW ACCESS FROM YOUR CLIENTS/a include /etc/squid/conf.d/*' -i /etc/squid/squid.conf; \
  sed -E 's|^access_log[[:space:]]+daemon:/var/log/squid/access.log[[:space:]]+squid.*$|# access_log disabled: use conf.d/99-logging.conf|' -i /etc/squid/squid.conf; \
  install -d -m 0750 -o ${SQUID_USER} -g ${SQUID_USER} /var/run/squid; \
  install -d -m 0755 -o root -g root /etc/squid/conf.d; \
  printf '%s\n' '# image placeholder, overridden by host bind mount ./conf.d' > /etc/squid/conf.d/00-placeholder.conf; \
  chown root:root /etc/squid/conf.d/00-placeholder.conf; \
  chmod 0644 /etc/squid/conf.d/00-placeholder.conf; \
  \
  # Drop install-time residue and non-runtime docs.
  apt-get clean; \
  rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/*; \
  rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* /usr/share/lintian/* /usr/share/locale/*

COPY --chown=root:root --chmod=0555 entrypoint.sh /usr/sbin/entrypoint.sh

STOPSIGNAL SIGTERM
EXPOSE 3128/tcp
USER ${SQUID_USER}
ENTRYPOINT ["/usr/sbin/entrypoint.sh"]
