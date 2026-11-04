FROM debian:trixie-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        debmirror \
        gnupg \
        gpgv \
        ca-certificates \
        debian-archive-keyring \
        ubuntu-keyring \
        rsync \
        wget \
        && \
        rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
