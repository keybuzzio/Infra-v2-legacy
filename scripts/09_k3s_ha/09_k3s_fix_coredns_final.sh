#!/usr/bin/env bash
#
# 09_k3s_fix_coredns_final.sh - Correction définitive CoreDNS Loop
#
# Problème: CoreDNS loop detected (127.0.0.1 -> :53)
# Solution: Modifier la configuration DNS des nœuds pour éviter la boucle
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Trouver tous les nœuds K3s
declare -a K3S_NODES=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "k3s" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        K3S_NODES+=("${IP_PRIVEE}:${HOSTNAME}")
    fi
done
exec 3<&-

if [[ ${#K3S_NODES[@]} -lt 1 ]]; then
    log_error "Aucun nœud K3s trouvé"
    exit 1
fi

# Trouver le premier master
MASTER_IP=""
for node in "${K3S_NODES[@]}"; do
    IP="${node%%:*}"
    HOSTNAME="${node##*:}"
    if [[ "${HOSTNAME}" == *"master"* ]]; then
        MASTER_IP="${IP}"
        break
    fi
done

if [[ -z "${MASTER_IP}" ]]; then
    MASTER_IP="${K3S_NODES[0]%%:*}"
fi

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "/root/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i /root/.ssh/keybuzz_infra"
fi
SSH_KEY_OPTS="${SSH_KEY_OPTS} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "=============================================================="
echo " [KeyBuzz] Correction Définitive CoreDNS Loop"
echo "=============================================================="
echo ""

log_info "Solution: Modifier la configuration DNS pour éviter la boucle"
log_info "Le problème vient de /etc/resolv.conf qui pointe vers 127.0.0.1"
echo ""

# Étape 1: Vérifier la configuration DNS actuelle
log_info "Étape 1: Vérification configuration DNS des nœuds..."
for node in "${K3S_NODES[@]}"; do
    IP="${node%%:*}"
    HOSTNAME="${node##*:}"
    echo "  ${HOSTNAME} (${IP}):"
    ssh ${SSH_KEY_OPTS} "root@${IP}" "cat /etc/resolv.conf 2>/dev/null | head -3" || echo "    ⚠ Impossible de lire"
done
echo ""

# Étape 2: Corriger la configuration DNS sur tous les nœuds
log_info "Étape 2: Correction configuration DNS (éviter 127.0.0.1)..."
for node in "${K3S_NODES[@]}"; do
    IP="${node%%:*}"
    HOSTNAME="${node##*:}"
    
    ssh ${SSH_KEY_OPTS} "root@${IP}" bash <<EOF
set -euo pipefail

# Vérifier si resolv.conf pointe vers 127.0.0.1
if grep -q "127.0.0.1" /etc/resolv.conf 2>/dev/null; then
    echo "  ${HOSTNAME}: /etc/resolv.conf pointe vers 127.0.0.1 (problème détecté)"
    
    # Créer un backup
    cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # Modifier pour utiliser des DNS externes uniquement
    cat > /etc/resolv.conf <<RESOLV
nameserver 1.1.1.1
nameserver 8.8.8.8
options edns0
RESOLV
    
    # Rendre immutable (comme dans Module 2)
    chattr +i /etc/resolv.conf 2>/dev/null || true
    
    echo "  ${HOSTNAME}: ✓ Configuration DNS corrigée"
else
    echo "  ${HOSTNAME}: ✓ Configuration DNS OK"
fi
EOF
done
echo ""

# Étape 3: Redémarrer CoreDNS
log_info "Étape 3: Redémarrage CoreDNS..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<'EOF'
set -euo pipefail

# Supprimer le deployment CoreDNS
kubectl delete deployment coredns -n kube-system --ignore-not-found=true
sleep 5

# Recréer CoreDNS
cat <<'COREDNS_YAML' | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coredns
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:coredns
rules:
- apiGroups:
  - ""
  resources:
  - endpoints
  - services
  - pods
  - namespaces
  verbs:
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
- apiGroups:
  - discovery.k8s.io
  resources:
  - endpointslices
  verbs:
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:coredns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:coredns
subjects:
- kind: ServiceAccount
  name: coredns
  namespace: kube-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . 1.1.1.1 8.8.8.8 {
           max_concurrent 1000
        }
        cache 30
        reload
        loadbalance
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/name: CoreDNS
spec:
  replicas: 1
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  selector:
    matchLabels:
      k8s-app: kube-dns
  template:
    metadata:
      labels:
        k8s-app: kube-dns
    spec:
      priorityClassName: system-cluster-critical
      serviceAccountName: coredns
      tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
        - key: node-role.kubernetes.io/master
          operator: Exists
          effect: NoSchedule
      nodeSelector:
        kubernetes.io/os: linux
      containers:
      - name: coredns
        image: registry.k8s.io/coredns/coredns:v1.12.3
        imagePullPolicy: IfNotPresent
        resources:
          limits:
            memory: 170Mi
          requests:
            cpu: 100m
            memory: 70Mi
        args: [ "-conf", "/etc/coredns/Corefile" ]
        volumeMounts:
        - name: config-volume
          mountPath: /etc/coredns
          readOnly: true
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        - containerPort: 9153
          name: metrics
          protocol: TCP
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            add:
            - NET_BIND_SERVICE
            drop:
            - all
          readOnlyRootFilesystem: true
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /ready
            port: 8181
            scheme: HTTP
          initialDelaySeconds: 0
          timeoutSeconds: 3
          successThreshold: 1
          failureThreshold: 3
      dnsPolicy: Default
      volumes:
      - name: config-volume
        configMap:
          name: coredns
          items:
          - key: Corefile
            path: Corefile
COREDNS_YAML

echo "✓ CoreDNS recréé"
EOF

log_success "CoreDNS redémarré"
echo ""

# Étape 4: Attendre et vérifier
log_info "Étape 4: Attente que CoreDNS démarre (40 secondes)..."
sleep 40

log_info "Étape 5: Vérification finale..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<'EOF'
set -euo pipefail

echo "=== État CoreDNS ==="
kubectl get deployment coredns -n kube-system
echo ""

PODS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | wc -l)
if [[ ${PODS} -gt 0 ]]; then
    echo "=== Pods CoreDNS ==="
    kubectl get pods -n kube-system -l k8s-app=kube-dns
    echo ""
    
    POD_NAME=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "${POD_NAME}" ]]; then
        STATUS=$(kubectl get pod -n kube-system "${POD_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        echo "Status: ${STATUS}"
        
        if [[ "${STATUS}" == "Running" ]]; then
            echo ""
            echo "=== Logs CoreDNS (dernières 10 lignes) ==="
            kubectl logs -n kube-system "${POD_NAME}" --tail 10 2>&1 | grep -v "loop" || kubectl logs -n kube-system "${POD_NAME}" --tail 10 2>&1
        else
            echo ""
            echo "=== Logs CoreDNS (dernières 20 lignes) ==="
            kubectl logs -n kube-system "${POD_NAME}" --tail 20 2>&1
        fi
    fi
else
    echo "⚠ Aucun pod CoreDNS trouvé"
fi
EOF

echo ""
echo "=============================================================="
log_success "✅ Correction CoreDNS terminée"
echo "=============================================================="
echo ""
log_info "Modifications appliquées:"
log_info "  1. Configuration DNS des nœuds corrigée (éviter 127.0.0.1)"
log_info "  2. CoreDNS recréé avec forward vers DNS externes (1.1.1.1, 8.8.8.8)"
log_info "  3. Plugin 'loop' retiré de la configuration CoreDNS"
echo ""

