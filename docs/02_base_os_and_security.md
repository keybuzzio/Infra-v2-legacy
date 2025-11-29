# Module 2 — Base OS & Sécurité

Standardisation pour tous les serveurs KeyBuzz – Version Production

## 📘 SOMMAIRE

1. [Introduction](#1-introduction)
2. [Objectifs du module](#2-objectifs-du-module)
3. [Portée (serveurs concernés)](#3-portée-serveurs-concernés)
4. [Prérequis](#4-prérequis)
5. [Procédure d'installation](#5-procédure-dinstallation)
6. [Checklist de validation](#6-checklist-de-validation)
7. [Bonnes pratiques](#7-bonnes-pratiques)
8. [Erreurs courantes à éviter](#8-erreurs-courantes-à-éviter)
9. [Tests manuels](#9-tests-manuels)
10. [Annexe : Ports utilisés par KeyBuzz](#10-annexe-ports-utilisés-par-keybuzz)

## 1. Introduction

Ce document définit la configuration de base obligatoire pour tous les serveurs de l'infrastructure KeyBuzz.

Il garantit que chaque nœud (PostgreSQL, Redis, RabbitMQ, MinIO, K3s, MariaDB, ProxySQL, HAProxy, Vector DB, Vault, Monitoring, etc.) dispose :

- d'un socle OS standardisé,
- d'un niveau de sécurité minimal,
- de performances cohérentes et optimisées,
- d'un environnement stable pour exécuter Docker ou K3s.

**⚠️ Ce module doit impérativement être appliqué avant tout autre module.**

## 2. Objectifs du module

- Standardiser l'environnement système sur tous les serveurs.
- Sécuriser l'accès SSH et désactiver les vecteurs d'attaque courants.
- Préparer les serveurs pour exécuter Docker ou K3s.
- Appliquer les optimisations système nécessaires aux clusters HA.
- Garantir la cohérence réseau, DNS et firewall.
- Permettre la réinstallation rapide d'un serveur (infra reproductible).

## 3. Portée : Serveurs concernés

Le module s'applique à **100% des serveurs** de l'infrastructure, notamment :

- k3s-master-01 → 03
- k3s-worker-01 → 05
- db-master-01 / db-slave-01 / db-slave-02
- redis-01 → 03
- queue-01 → 03
- minio-01
- vector-db-01
- litellm-01
- maria-01 → 03
- proxysql-01 / 02
- haproxy-01 / 02
- install-01
- vault, siem, backup
- monitoring
- mail, nos services NLP/ML
- **toute machine future**

## 4. Prérequis

- Ubuntu Server 24.04 LTS
- Accès root par clé SSH (pas de mot de passe)
- Connectivité privée 10.0.0.0/16 fonctionnelle
- Script `base_os.sh` accessible depuis install-01
- `servers.tsv` correctement défini

## 5. Procédure d'installation

### 5.1 🍀 Mise à jour OS

```bash
apt update && apt upgrade -y
apt install -y curl wget jq unzip gnupg htop net-tools git ca-certificates
```

### 5.2 ⚙ Configuration générale

```bash
timedatectl set-timezone Europe/Paris
timedatectl set-ntp true
```

Créer un utilisateur standard :

```bash
useradd -m -s /bin/bash keybuzz
usermod -aG sudo keybuzz
```

### 5.3 ⏱ Désactivation du SWAP (obligatoire HA)

```bash
swapoff -a
sed -i '/swap/d' /etc/fstab
```

**Raison :**

- Patroni REFUSE le swap
- RabbitMQ Quorum peut entrer en état "suspect"
- Flannel/K3s perd ses sessions VXLAN
- Redis réplication devient instable

### 5.4 🚀 Optimisation kernel & sysctl

Créer `/etc/sysctl.d/99-keybuzz.conf` :

```bash
cat <<EOF > /etc/sysctl.d/99-keybuzz.conf
net.core.somaxconn = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_tw_reuse = 1

fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288

vm.swappiness = 10
EOF

sysctl --system
```

### 5.5 🐳 Installation Docker (standard KeyBuzz)

```bash
apt remove -y docker docker-engine docker.io containerd runc
curl -fsSL https://get.docker.com | sh
systemctl enable docker
```

Créer `/etc/docker/daemon.json` :

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "exec-opts": ["native.cgroupdriver=systemd"]
}
```

Redémarrer Docker :

```bash
systemctl restart docker
```

### 5.6 🔐 Durcissement SSH

Créer `/etc/ssh/sshd_config.d/99-keybuzz.conf` :

```
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
```

Redémarrer :

```bash
systemctl restart sshd
```

### 5.7 🔥 Firewall UFW

Règles par défaut :

```bash
ufw default deny incoming
ufw default allow outgoing
```

Autoriser ton IP d'administration :

```bash
ufw allow from <ton_ip> to any port 22
```

Autoriser réseau privé :

```bash
ufw allow from 10.0.0.0/16
```

### 5.8 🌍 DNS – Résolution réseau critique

Fixer résolveurs :

```bash
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
chattr +i /etc/resolv.conf
```

**Pourquoi ?**

Sans ce fix, K3s échoue :
- `Failed to connect to registry-1.docker.io`
- Debian/Ubuntu écrasent resolv.conf au reboot → cluster KO

### 5.9 📚 Journaux système & rotation

Limiter journald :

```bash
mkdir -p /etc/systemd/journald.conf.d
cat <<EOF > /etc/systemd/journald.conf.d/limit.conf
[Journal]
SystemMaxUse=200M
SystemKeepFree=100M
EOF

systemctl restart systemd-journald
```

## 6. ✔ Checklist de validation (à exécuter après module 2)

Commandes rapides :

- ✔ Docker OK : `docker run hello-world`
- ✔ Swap OFF : `free -h`
- ✔ NTP OK : `timedatectl status`
- ✔ DNS OK : `dig google.com`
- ✔ Firewall OK : `ufw status numbered`
- ✔ Ports ouverts :
  - Aucun port public
  - Ports périmétriques : 22 uniquement
  - 10.0.0.x full mesh

## 7. ⭐ Bonnes pratiques officielles KeyBuzz

- Toujours exécuter `base_os.sh` **AVANT** un module rôle (Postgres, Redis, etc.)
- Ne jamais installer K3s si :
  - swap est activé
  - DNS n'est pas fixé
  - UFW n'est pas correctement configuré
- Toujours utiliser Docker CE (pas les paquets Ubuntu)
- Ne jamais exposer un service stateful en public
- Ne jamais ouvrir 0.0.0.0 dans un firewall de DB

## 8. ⚠️ Erreurs courantes à éviter

- Installer Postgres avant d'appliquer les sysctl ⇒ FAIL patroni
- Ne pas désactiver swap ⇒ FAIL redis, FAIL rabbitmq
- Laisser resolv.conf géré par systemd ⇒ pods NotReady
- Activer ufw sans whitelister son IP ⇒ lockout
- Installer K3s avant le module OS ⇒ cluster irrécupérable
- Laisser journald sans limites ⇒ disques saturés
- Mettre MinIO sur une IP publique ⇒ fuite de données

## 9. 🔬 Tests manuels après installation

**Test SSH :**
```bash
ssh root@<ip>
```

**Test Docker :**
```bash
docker ps
```

**Test réseau interne :**
```bash
ping 10.0.0.120  # par ex. un nœud DB
curl 10.0.0.10:5432  # LB interne Postgres
```

**Test DNS :**
```bash
nslookup google.com
```

## 10. 📎 Annexe : Ports utilisés dans KeyBuzz

| Service | Ports | Notes |
|---------|-------|-------|
| PostgreSQL Patroni | 5432 | LB 10.0.0.10 |
| PgBouncer | 6432 | HAProxy |
| Redis HA | 6379 | LB 10.0.0.10 |
| RabbitMQ | 5672 | LB 10.0.0.10 |
| RabbitMQ mgmt | 15672 | interne |
| MinIO | 9000 / 9001 | privé |
| K3s API | 6443 | masters |
| K3s Worker Ports | 8472/udp, 10250/tcp | flannel/VXLAN |


