#!/usr/bin/env bash
# Script pour construire l'image Docker Patroni sur un nœud DB

set -euo pipefail

cd /opt/keybuzz/patroni

cat > Dockerfile <<'DOCKERFILE'
FROM postgres:16

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3-pip \
        python3-dev \
        python3-psycopg2 \
        python3-setuptools \
        python3-wheel \
        gcc \
        postgresql-server-dev-16 \
        git \
        ca-certificates && \
    pip3 install --break-system-packages --no-cache-dir \
        patroni[raft]==3.3.2 \
        psycopg2-binary && \
    apt-get remove -y gcc git && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        postgresql-16-pgvector && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/postgresql && \
    chown -R postgres:postgres /var/run/postgresql

USER postgres

CMD ["patroni", "/etc/patroni/patroni.yml"]
DOCKERFILE

echo "Construction de l'image Docker patroni-pg16-raft:latest..."
docker build -t patroni-pg16-raft:latest . 2>&1 | tee /tmp/patroni_build.log

if [ $? -eq 0 ]; then
    echo "✓ Image construite avec succès"
    docker images | grep patroni-pg16-raft
else
    echo "✗ Échec de la construction de l'image"
    cat /tmp/patroni_build.log
    exit 1
fi

