#!/usr/bin/env bash
#
# base_os.sh - Standardisation OS & sécurité pour tous les serveurs KeyBuzz
#
# Usage:
#   ./base_os.sh <ROLE> <SUBROLE>
# Exemple:
#   ./base_os.sh db postgres
#
# Ce script DOIT être exécuté en root sur chaque nœud.

set -euo pipefail

ROLE="${1:-generic}"
SUBROLE="${2:-generic}"

# IP publique d'administration (install-01 comme point d'entrée)
# Peut être modifiée pour une IP spécifique si nécessaire
ADMIN_IP="91.98.128.153"
PRIVATE_CIDR="10.0.0.0/16"
TIMEZONE="Europe/Paris"

echo "========== [KeyBuzz] Module 2 - Base OS & Sécurité =========="
echo "Rôle: ${ROLE}, Sous-rôle: ${SUBROLE}"
echo "=============================================================="

if [[ "$(id -u)" -ne 0 ]]; then
  echo "❌ Ce script doit être exécuté en root."
  exit 1
fi

###############################################################################
# 1. Mise à jour OS & paquets de base
###############################################################################
echo "[1/9] Mise à jour du système & paquets de base..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

apt-get install -y \
  curl wget jq unzip gnupg htop net-tools git ca-certificates \
  software-properties-common ufw fail2ban auditd

###############################################################################
# 2. Timezone & NTP
###############################################################################
echo "[2/9] Configuration timezone & NTP..."

timedatectl set-timezone "${TIMEZONE}" || true
timedatectl set-ntp true || true

###############################################################################
# 3. Désactivation du swap
###############################################################################
echo "[3/9] Désactivation du swap..."

if swapon --summary | grep -q .; then
  swapoff -a || true
fi

# Supprimer les entrées swap dans /etc/fstab
if grep -q "swap" /etc/fstab; then
  sed -i.bak '/swap/d' /etc/fstab
fi

###############################################################################
# 4. Optimisation kernel & sysctl
###############################################################################
echo "[4/9] Application des paramètres sysctl..."

mkdir -p /etc/sysctl.d

cat <<'EOF' > /etc/sysctl.d/99-keybuzz.conf
net.core.somaxconn = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_tw_reuse = 1

fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288

vm.swappiness = 10
EOF

sysctl --system

###############################################################################
# 5. Installation & configuration Docker
###############################################################################
echo "[5/9] Installation / configuration Docker..."

if ! command -v docker >/dev/null 2>&1; then
  # Supprimer éventuellement les vieilles versions
  apt-get remove -y docker docker-engine docker.io containerd runc || true

  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
fi

mkdir -p /etc/docker

cat <<'EOF' > /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF

systemctl restart docker

###############################################################################
# 6. Durcissement SSH
###############################################################################
echo "[6/9] Durcissement SSH..."

mkdir -p /etc/ssh/sshd_config.d

cat <<'EOF' > /etc/ssh/sshd_config.d/99-keybuzz.conf
PermitRootLogin prohibit-password
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
AllowTcpForwarding no
X11Forwarding no
UseDNS no
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 4
EOF

systemctl restart sshd || true

###############################################################################
# 7. Firewall UFW
###############################################################################
echo "[7/9] Configuration UFW..."

# Réinitialiser proprement (sans casser une éventuelle conf existante)
ufw --force reset || true

# Politique par défaut
ufw default deny incoming
ufw default allow outgoing

# SSH depuis IP admin
if [[ -n "${ADMIN_IP}" && "${ADMIN_IP}" != "XXX.YYY.ZZZ.TTT" ]]; then
  ufw allow from "${ADMIN_IP}" to any port 22 proto tcp
fi

# SSH & trafic interne depuis le réseau privé
ufw allow from "${PRIVATE_CIDR}" to any port 22 proto tcp
ufw allow from "${PRIVATE_CIDR}"

###############################################################################
# 7.1 Ouverture des ports par rôle
###############################################################################
echo "[7/9] Ouverture des ports spécifiques au rôle..."

case "${ROLE}" in
  db)
    case "${SUBROLE}" in
      postgres)
        # PostgreSQL + PgBouncer (accès interne uniquement)
        ufw allow from "${PRIVATE_CIDR}" to any port 5432 proto tcp
        ufw allow from "${PRIVATE_CIDR}" to any port 6432 proto tcp
        ;;
      mariadb)
        ufw allow from "${PRIVATE_CIDR}" to any port 3306 proto tcp
        # Galera ports sera géré dans le module MariaDB
        ;;
      *)
        ;;
    esac
    ;;
  redis)
    ufw allow from "${PRIVATE_CIDR}" to any port 6379 proto tcp
    ;;
  queue)
    # RabbitMQ
    ufw allow from "${PRIVATE_CIDR}" to any port 5672 proto tcp
    # UI 15672 resterait interne, à ouvrir ou non plus tard
    ;;
  storage)
    case "${SUBROLE}" in
      minio)
        ufw allow from "${PRIVATE_CIDR}" to any port 9000 proto tcp
        ufw allow from "${PRIVATE_CIDR}" to any port 9001 proto tcp
        ;;
      *)
        ;;
    esac
    ;;
  k8s)
    case "${SUBROLE}" in
      master)
        # Kubernetes API server
        ufw allow 6443/tcp
        # Kubelet API
        ufw allow 10250/tcp
        # etcd client/server
        ufw allow 2379:2380/tcp
        # kube-scheduler
        ufw allow 10259/tcp
        # kube-controller-manager
        ufw allow 10257/tcp
        ;;
      worker)
        # Kubelet API
        ufw allow 10250/tcp
        # NodePort services (optionnel, pour services NodePort)
        ufw allow 30000:32767/tcp
        ;;
      *)
        ;;
    esac
    ;;
  lb)
    # HAProxy interne ou API Gateway
    ufw allow from "${PRIVATE_CIDR}" to any port 5432 proto tcp || true
    ufw allow from "${PRIVATE_CIDR}" to any port 5672 proto tcp || true
    ufw allow from "${PRIVATE_CIDR}" to any port 6379 proto tcp || true
    ;;
  monitoring)
    # Prometheus qui scrapera les exporters
    ;;
  security|backup|apps|ai|analytics|mail|dev|orchestrator)
    # Règles spécifiques dans les modules suivants
    ;;
  *)
    ;;
esac

# Activer UFW
ufw --force enable

###############################################################################
# 8. DNS & résolution
###############################################################################
echo "[8/9] Configuration DNS..."

# On enlève l'immuabilité potentielle
chattr -i /etc/resolv.conf 2>/dev/null || true

# Nettoyage minimal : si aucun nameserver 1.1.1.1 ou 8.8.8.8, on les ajoute
if ! grep -q "1.1.1.1" /etc/resolv.conf; then
  echo "nameserver 1.1.1.1" >> /etc/resolv.conf
fi
if ! grep -q "8.8.8.8" /etc/resolv.conf; then
  echo "nameserver 8.8.8.8" >> /etc/resolv.conf
fi

# On verrouille pour éviter que systemd-resolved réécrive
chattr +i /etc/resolv.conf || true

###############################################################################
# 9. Journaux système
###############################################################################
echo "[9/9] Configuration journald..."

mkdir -p /etc/systemd/journald.conf.d

cat <<'EOF' > /etc/systemd/journald.conf.d/limit.conf
[Journal]
SystemMaxUse=200M
SystemKeepFree=100M
EOF

systemctl restart systemd-journald || true

echo "=============================================================="
echo "✅ [KeyBuzz] Base OS & Sécurité appliqués avec succès."
echo "   Rôle: ${ROLE} / ${SUBROLE}"
echo "=============================================================="

