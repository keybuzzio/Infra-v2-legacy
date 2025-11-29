# Module 2 : Base OS & Sécurité - Documentation Technique Complète

**Date de création** : 2025-11-25  
**Version** : 2.0 (Installation depuis serveurs vierges)  
**Statut** : ✅ Documentation complète

---

## 🎯 Objectif du Module

Standardiser et sécuriser **TOUS** les serveurs de l'infrastructure KeyBuzz avant l'installation de tout autre module. Ce module est **OBLIGATOIRE EN PREMIER** et doit être appliqué sur **100% des serveurs**.

### Objectifs Spécifiques

1. **Standardisation OS** : Ubuntu 24.04 LTS uniforme
2. **Sécurité** : Durcissement SSH, firewall UFW, fail2ban
3. **Préparation Docker** : Installation et configuration Docker CE
4. **Préparation Kubernetes** : Prérequis pour K8s (swap désactivé, DNS fixe, sysctl)
5. **Optimisations** : Kernel, réseau, performances
6. **Cohérence** : DNS, timezone, logs

---

## 📐 Architecture

### Portée

**100% des serveurs** de l'infrastructure KeyBuzz, notamment :

- **K8s** : k8s-master-01 à 03, k8s-worker-01 à 05
- **PostgreSQL** : db-master-01, db-slave-01, db-slave-02
- **Redis** : redis-01 à 03
- **RabbitMQ** : queue-01 à 03
- **MinIO** : minio-01 à 03
- **MariaDB** : maria-01 à 03
- **ProxySQL** : proxysql-01, proxysql-02
- **HAProxy** : haproxy-01, haproxy-02
- **Autres** : install-01, backup-01, etc.

**Total** : ~50 serveurs

---

## 🔧 Versions et Technologies

### Système d'Exploitation

- **Distribution** : Ubuntu Server 24.04 LTS (Noble Numbat)
- **Kernel** : Linux 6.8.0-71-generic (ou équivalent)
- **Architecture** : x86_64 (AMD64)

### Paquets Installés

| Paquet | Version | Description |
|--------|---------|-------------|
| curl | latest | Client HTTP |
| wget | latest | Téléchargement fichiers |
| jq | latest | Parser JSON |
| unzip | latest | Décompression |
| gnupg | latest | Gestion clés |
| htop | latest | Monitoring système |
| net-tools | latest | Outils réseau |
| git | latest | Contrôle de version |
| ca-certificates | latest | Certificats SSL |
| software-properties-common | latest | Gestion dépôts |
| ufw | latest | Firewall |
| fail2ban | latest | Protection SSH |
| auditd | latest | Audit système |
| docker-ce | 24.x | Docker Engine |

### Docker

- **Version** : 24.x (dernière stable)
- **Installation** : Via script officiel `get.docker.com`
- **Storage Driver** : overlay2
- **Cgroup Driver** : systemd

---

## ⚙️ Configuration Détaillée

### 1. Mise à Jour OS & Paquets de Base

**Commandes** :
```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

apt-get install -y \
  curl wget jq unzip gnupg htop net-tools git ca-certificates \
  software-properties-common ufw fail2ban auditd
```

**Résultat attendu** :
- Tous les paquets installés
- Système à jour
- Aucune erreur

**Vérification** :
```bash
dpkg -l | grep -E "curl|wget|jq|ufw|docker"
```

---

### 2. Configuration Timezone & NTP

**Commandes** :
```bash
timedatectl set-timezone Europe/Paris
timedatectl set-ntp true
```

**Résultat attendu** :
- Timezone : `Europe/Paris`
- NTP activé : `yes`

**Vérification** :
```bash
timedatectl status
```

**⚠️ CRITIQUE** : Obligatoire pour Patroni, Redis Sentinel, RabbitMQ quorum, MariaDB Galera, Kubernetes. La synchronisation temporelle est essentielle pour les clusters HA.

---

### 3. Désactivation du Swap

**Commandes** :
```bash
swapoff -a
sed -i.bak '/swap/d' /etc/fstab
```

**Résultat attendu** :
- Swap désactivé immédiatement
- Entrées swap supprimées de `/etc/fstab`

**Vérification** :
```bash
swapon --summary  # Doit être vide
grep -i swap /etc/fstab  # Ne doit pas contenir de swap
```

**⚠️ CRITIQUE** : Obligatoire pour :
- Patroni (refuse de démarrer avec swap)
- RabbitMQ quorum (refuse de démarrer avec swap)
- Kubernetes (refuse de démarrer avec swap)

---

### 4. Optimisations Kernel & sysctl

**Fichier** : `/etc/sysctl.d/99-keybuzz.conf`

**Contenu** :
```conf
net.core.somaxconn = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_tw_reuse = 1

fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288

vm.swappiness = 10
```

**Application** :
```bash
sysctl --system
```

**Résultat attendu** :
- Paramètres appliqués
- Pas d'erreur

**Vérification** :
```bash
sysctl net.core.somaxconn  # Doit afficher 65535
sysctl vm.swappiness  # Doit afficher 10
```

**Explication** :
- `somaxconn` : Augmente la capacité de connexions simultanées
- `tcp_tw_reuse` : Réutilise les connexions TIME_WAIT
- `inotify` : Augmente les limites pour les watchers de fichiers
- `swappiness` : Réduit l'utilisation du swap (même s'il est désactivé)

---

### 5. Installation & Configuration Docker

**Installation** :
```bash
# Supprimer éventuellement les vieilles versions
apt-get remove -y docker docker-engine docker.io containerd runc || true

# Installer Docker CE
curl -fsSL https://get.docker.com | sh
systemctl enable docker
```

**Configuration** : `/etc/docker/daemon.json`

**Contenu** :
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

**Redémarrage** :
```bash
systemctl restart docker
```

**Résultat attendu** :
- Docker installé et actif
- Version 24.x
- Storage driver : overlay2
- Cgroup driver : systemd

**Vérification** :
```bash
docker --version
docker info | grep -E "Storage Driver|Cgroup Driver"
systemctl is-active docker  # Doit être active
```

**⚠️ IMPORTANT** :
- `cgroupdriver=systemd` : Obligatoire pour Kubernetes
- `storage-driver=overlay2` : Recommandé pour performances

---

### 6. Durcissement SSH

**Fichier** : `/etc/ssh/sshd_config.d/99-keybuzz.conf`

**Contenu** :
```conf
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

**Redémarrage** :
```bash
systemctl restart sshd
```

**Résultat attendu** :
- SSH configuré avec sécurité renforcée
- Authentification par clé uniquement
- Pas d'authentification par mot de passe

**Vérification** :
```bash
sshd -T | grep -E "PasswordAuthentication|PermitRootLogin"
# Doit afficher : PasswordAuthentication no, PermitRootLogin prohibit-password
```

**Explication** :
- `PermitRootLogin prohibit-password` : Root peut se connecter uniquement par clé
- `PasswordAuthentication no` : Désactive l'authentification par mot de passe
- `UseDNS no` : Évite les délais de résolution DNS
- `ClientAliveInterval` : Détecte les connexions mortes

---

### 7. Firewall UFW

**Configuration** :

```bash
# Réinitialiser proprement
ufw --force reset || true

# Politique par défaut
ufw default deny incoming
ufw default allow outgoing

# SSH depuis IP admin
ufw allow from ${ADMIN_IP} to any port 22 proto tcp

# SSH & trafic interne depuis le réseau privé
ufw allow from 10.0.0.0/16 to any port 22 proto tcp
ufw allow from 10.0.0.0/16
```

**Ouverture des ports par rôle** :

#### PostgreSQL (ROLE=db, SUBROLE=postgres)
```bash
ufw allow from 10.0.0.0/16 to any port 5432 proto tcp  # PostgreSQL
ufw allow from 10.0.0.0/16 to any port 6432 proto tcp  # PgBouncer
```

#### MariaDB (ROLE=db, SUBROLE=mariadb)
```bash
ufw allow from 10.0.0.0/16 to any port 3306 proto tcp  # MariaDB
```

#### Redis (ROLE=redis)
```bash
ufw allow from 10.0.0.0/16 to any port 6379 proto tcp  # Redis
ufw allow from 10.0.0.0/16 to any port 26379 proto tcp  # Sentinel
```

#### RabbitMQ (ROLE=queue)
```bash
ufw allow from 10.0.0.0/16 to any port 5672 proto tcp  # RabbitMQ AMQP
ufw allow from 10.0.0.0/16 to any port 15672 proto tcp  # Management UI
```

#### MinIO (ROLE=storage, SUBROLE=minio)
```bash
ufw allow from 10.0.0.0/16 to any port 9000 proto tcp  # S3 API
ufw allow from 10.0.0.0/16 to any port 9001 proto tcp  # Console
```

#### Kubernetes (ROLE=k3s) ⚠️ ADAPTÉ POUR K8s

**⚠️ IMPORTANT** : Pour K8s (pas K3s), les ports sont différents :

**Masters (SUBROLE=master)** :
```bash
ufw allow 6443/tcp          # API server Kubernetes
ufw allow 10250/tcp         # Kubelet API
ufw allow 2379:2380/tcp      # etcd client/server
ufw allow 10259/tcp          # kube-scheduler
ufw allow 10257/tcp          # kube-controller-manager
```

**Workers (SUBROLE=worker)** :
```bash
ufw allow 10250/tcp         # Kubelet API
ufw allow 30000:32767/tcp    # NodePort services (optionnel)
```

**⚠️ NOTE** : Pour Calico IPIP, pas besoin de port UDP spécifique (contrairement à Flannel VXLAN).

#### HAProxy (ROLE=lb)
```bash
ufw allow from 10.0.0.0/16 to any port 5432 proto tcp  # PostgreSQL
ufw allow from 10.0.0.0/16 to any port 5672 proto tcp  # RabbitMQ
ufw allow from 10.0.0.0/16 to any port 6379 proto tcp  # Redis
```

**Activation** :
```bash
ufw --force enable
```

**Résultat attendu** :
- UFW actif
- Règles appliquées selon le rôle
- Trafic interne autorisé (10.0.0.0/16)
- Trafic externe bloqué (sauf SSH depuis ADMIN_IP)

**Vérification** :
```bash
ufw status verbose
```

---

### 8. DNS & Résolution

**Configuration** : `/etc/resolv.conf`

**Contenu** :
```
nameserver 1.1.1.1
nameserver 8.8.8.8
```

**Commandes** :
```bash
# Enlever l'immuabilité potentielle
chattr -i /etc/resolv.conf 2>/dev/null || true

# Ajouter les DNS si absents
if ! grep -q "1.1.1.1" /etc/resolv.conf; then
  echo "nameserver 1.1.1.1" >> /etc/resolv.conf
fi
if ! grep -q "8.8.8.8" /etc/resolv.conf; then
  echo "nameserver 8.8.8.8" >> /etc/resolv.conf
fi

# Verrouiller pour éviter que systemd-resolved réécrive
chattr +i /etc/resolv.conf || true
```

**Résultat attendu** :
- DNS fixe configuré : 1.1.1.1, 8.8.8.8
- Fichier verrouillé (immutable)

**Vérification** :
```bash
cat /etc/resolv.conf
# Doit contenir : nameserver 1.1.1.1 et nameserver 8.8.8.8

lsattr /etc/resolv.conf
# Doit afficher : ----i--------- (i = immutable)
```

**⚠️ CRITIQUE** : Obligatoire avant Kubernetes. CoreDNS a besoin de DNS fonctionnels pour résoudre les services externes.

---

### 9. Journaux Système (journald)

**Fichier** : `/etc/systemd/journald.conf.d/limit.conf`

**Contenu** :
```conf
[Journal]
SystemMaxUse=200M
SystemKeepFree=100M
```

**Redémarrage** :
```bash
systemctl restart systemd-journald
```

**Résultat attendu** :
- Limite de taille des journaux : 200M
- Espace libre réservé : 100M

**Vérification** :
```bash
journalctl --disk-usage
```

---

## 🚀 Processus d'Installation

### Prérequis

1. **Accès SSH** : Accès root sans mot de passe vers tous les serveurs
2. **Clé SSH** : Clé SSH déposée sur tous les serveurs
3. **Réseau** : Réseau privé 10.0.0.0/16 fonctionnel
4. **Inventaire** : Fichier `servers.tsv` correctement rempli

### Étape 1 : Préparation sur install-01

```bash
# Se connecter sur install-01
ssh root@install-01

# Aller dans l'espace de travail V2
cd /opt/keybuzz-installer-v2

# Vérifier que servers.tsv est présent
ls -la inventory/servers.tsv

# Vérifier que les scripts sont présents
ls -la scripts/02_base_os_and_security/
```

### Étape 2 : Vérification de l'Accès SSH

```bash
# Tester l'accès SSH à quelques serveurs
ssh root@10.0.0.100 "hostname"  # k8s-master-01
ssh root@10.0.0.120 "hostname"  # db-master-01
ssh root@10.0.0.123 "hostname"  # redis-01
```

### Étape 3 : Configuration ADMIN_IP

**Fichier** : `scripts/02_base_os_and_security/base_os.sh`

**Ligne 19** :
```bash
ADMIN_IP="91.98.128.153"  # IP publique d'install-01
```

**⚠️ Vérifier** : Cette IP doit correspondre à l'IP publique d'install-01.

### Étape 4 : Exécution de l'Installation

```bash
cd /opt/keybuzz-installer-v2/scripts/02_base_os_and_security

# Mode parallèle (10 serveurs simultanés, recommandé)
./apply_base_os_to_all.sh ../../inventory/servers.tsv

# OU mode séquentiel (1 serveur à la fois, plus lent mais plus sûr)
./apply_base_os_to_all.sh ../../inventory/servers.tsv --sequential
```

**Durée estimée** :
- Mode parallèle : ~10-15 minutes pour 50 serveurs
- Mode séquentiel : ~30-45 minutes pour 50 serveurs

### Étape 5 : Vérification

```bash
# Vérifier les logs
ls -la /tmp/module2_*.log

# Vérifier un serveur spécifique
ssh root@10.0.0.100 "docker --version && ufw status | head -5"
```

---

## ✅ Tests de Validation

### Test 1 : Docker Installé

**Commande** :
```bash
ssh root@${SERVER_IP} "docker --version"
```

**Résultat attendu** :
```
Docker version 24.x.x, build xxxxx
```

**Statut** : ✅ Réussi si version affichée

---

### Test 2 : Swap Désactivé

**Commande** :
```bash
ssh root@${SERVER_IP} "swapon --summary"
```

**Résultat attendu** :
```
(rien, vide)
```

**Statut** : ✅ Réussi si vide

---

### Test 3 : UFW Actif

**Commande** :
```bash
ssh root@${SERVER_IP} "ufw status | head -3"
```

**Résultat attendu** :
```
Status: active
```

**Statut** : ✅ Réussi si "active"

---

### Test 4 : DNS Fixe

**Commande** :
```bash
ssh root@${SERVER_IP} "cat /etc/resolv.conf"
```

**Résultat attendu** :
```
nameserver 1.1.1.1
nameserver 8.8.8.8
```

**Statut** : ✅ Réussi si les deux DNS présents

---

### Test 5 : SSH Durci

**Commande** :
```bash
ssh root@${SERVER_IP} "sshd -T | grep PasswordAuthentication"
```

**Résultat attendu** :
```
passwordauthentication no
```

**Statut** : ✅ Réussi si "no"

---

### Test 6 : Timezone

**Commande** :
```bash
ssh root@${SERVER_IP} "timedatectl | grep 'Time zone'"
```

**Résultat attendu** :
```
Time zone: Europe/Paris (CET, +0100)
```

**Statut** : ✅ Réussi si "Europe/Paris"

---

### Test 7 : NTP Actif

**Commande** :
```bash
ssh root@${SERVER_IP} "timedatectl | grep 'NTP service'"
```

**Résultat attendu** :
```
NTP service: active
```

**Statut** : ✅ Réussi si "active"

---

### Test 8 : Sysctl Appliqués

**Commande** :
```bash
ssh root@${SERVER_IP} "sysctl net.core.somaxconn"
```

**Résultat attendu** :
```
net.core.somaxconn = 65535
```

**Statut** : ✅ Réussi si "65535"

---

## 📊 Résultats des Tests

| Test | Commande | Résultat Attendu | Criticité |
|------|----------|------------------|-----------|
| Docker installé | `docker --version` | Version 24.x | ⚠️ Critique |
| Swap désactivé | `swapon --summary` | Vide | ⚠️ Critique |
| UFW actif | `ufw status` | Status: active | ⚠️ Critique |
| DNS fixe | `cat /etc/resolv.conf` | 1.1.1.1, 8.8.8.8 | ⚠️ Critique |
| SSH durci | `sshd -T \| grep PasswordAuthentication` | no | ✅ Important |
| Timezone | `timedatectl` | Europe/Paris | ✅ Important |
| NTP actif | `timedatectl` | NTP service: active | ⚠️ Critique |
| Sysctl | `sysctl net.core.somaxconn` | 65535 | ✅ Important |

---

## 🔗 Points d'Accès

### Réseau Privé

- **CIDR** : `10.0.0.0/16`
- **Accès autorisé** : Tous les serveurs du réseau privé
- **Ports ouverts** : Selon le rôle (voir section UFW)

### SSH

- **Depuis ADMIN_IP** : `91.98.128.153` (install-01)
- **Depuis réseau privé** : `10.0.0.0/16`
- **Port** : 22
- **Authentification** : Clé SSH uniquement

---

## 🔒 Règles Définitives

### ⚠️ NE PLUS MODIFIER

1. **Versions** : Ubuntu 24.04 LTS, Docker 24.x
2. **Swap** : Toujours désactivé
3. **DNS** : Toujours 1.1.1.1, 8.8.8.8 (fixe, immutable)
4. **SSH** : Toujours durci (pas de mot de passe)
5. **UFW** : Toujours actif avec règles par rôle

### ✅ Utilisation

**Tous les serveurs doivent avoir** :
- Docker installé et fonctionnel
- Swap désactivé
- UFW actif
- DNS fixe
- SSH durci
- Timezone/NTP configurés

---

## 🐛 Dépannage

### Problème 1 : Docker ne démarre pas

**Symptômes** :
- `systemctl status docker` : failed
- Erreur : `Failed to start Docker Application Container Engine`

**Diagnostic** :
```bash
journalctl -u docker --no-pager -n 50
```

**Solutions** :
1. Vérifier les prérequis :
   ```bash
   modprobe overlay
   modprobe br_netfilter
   ```

2. Vérifier la configuration :
   ```bash
   cat /etc/docker/daemon.json
   ```

3. Réinstaller Docker :
   ```bash
   apt-get remove -y docker docker-engine docker.io containerd runc
   curl -fsSL https://get.docker.com | sh
   ```

---

### Problème 2 : Swap toujours actif

**Symptômes** :
- `swapon --summary` affiche encore des partitions

**Diagnostic** :
```bash
swapon --summary
cat /etc/fstab | grep swap
```

**Solution** :
```bash
swapoff -a
sed -i.bak '/swap/d' /etc/fstab
# Vérifier qu'aucune partition swap n'est montée
```

---

### Problème 3 : DNS réécrit par systemd-resolved

**Symptômes** :
- `/etc/resolv.conf` réécrit après redémarrage
- DNS incorrects

**Diagnostic** :
```bash
lsattr /etc/resolv.conf
systemctl status systemd-resolved
```

**Solution** :
```bash
# Désactiver systemd-resolved (si nécessaire)
systemctl stop systemd-resolved
systemctl disable systemd-resolved

# Verrouiller /etc/resolv.conf
chattr +i /etc/resolv.conf
```

---

### Problème 4 : UFW bloque le trafic interne

**Symptômes** :
- Serveurs ne peuvent pas communiquer entre eux
- Timeout sur connexions réseau

**Diagnostic** :
```bash
ufw status verbose
```

**Solution** :
```bash
# Autoriser le réseau privé
ufw allow from 10.0.0.0/16
ufw reload
```

---

### Problème 5 : SSH refuse la connexion après durcissement

**Symptômes** :
- Impossible de se connecter en SSH
- Erreur : `Permission denied`

**Diagnostic** :
```bash
# Depuis un autre serveur
ssh -v root@${SERVER_IP}
```

**Solution** :
1. Vérifier que la clé SSH est bien déposée
2. Vérifier les permissions :
   ```bash
   chmod 600 ~/.ssh/authorized_keys
   chmod 700 ~/.ssh
   ```
3. Vérifier la configuration SSH :
   ```bash
   sshd -T | grep -E "PasswordAuthentication|PermitRootLogin"
   ```

---

## 📚 Références

### Documents de Référence

- `Context/Context.txt` - Spécification technique complète
- `Infra/scripts/RAPPORT_TECHNIQUE_COMPLET_KEYBUZZ_INFRASTRUCTURE.md` - Rapport technique
- `Infra/docs/02_base_os_and_security.md` - Documentation existante

### Scripts

- `scripts/02_base_os_and_security/base_os.sh` - Script d'installation
- `scripts/02_base_os_and_security/apply_base_os_to_all.sh` - Script maître

---

## ✅ Checklist de Validation

### Après Installation

- [ ] Docker installé sur tous les serveurs
- [ ] Swap désactivé sur tous les serveurs
- [ ] UFW actif sur tous les serveurs
- [ ] DNS fixe configuré sur tous les serveurs
- [ ] SSH durci sur tous les serveurs
- [ ] Timezone configurée (Europe/Paris)
- [ ] NTP actif sur tous les serveurs
- [ ] Sysctl appliqués sur tous les serveurs
- [ ] Journald configuré sur tous les serveurs
- [ ] Tous les serveurs accessibles via SSH

### Tests de Validation

- [ ] Test Docker : ✅
- [ ] Test Swap : ✅
- [ ] Test UFW : ✅
- [ ] Test DNS : ✅
- [ ] Test SSH : ✅
- [ ] Test Timezone : ✅
- [ ] Test NTP : ✅
- [ ] Test Sysctl : ✅

---

## 🎯 Conclusion

✅ **Le Module 2 est la base fondamentale de l'infrastructure KeyBuzz.**

**Tous les serveurs doivent avoir** :
- ✅ Base OS standardisée (Ubuntu 24.04)
- ✅ Docker installé et configuré
- ✅ Sécurité renforcée (SSH, UFW)
- ✅ Prérequis pour Kubernetes (swap désactivé, DNS fixe)
- ✅ Optimisations système

**Prochaine étape** : Module 3 - PostgreSQL HA (Patroni RAFT)

---

**Documentation générée le** : 2025-11-25  
**Version** : 2.0  
**Statut** : ✅ **COMPLÈTE ET PRÊTE**

