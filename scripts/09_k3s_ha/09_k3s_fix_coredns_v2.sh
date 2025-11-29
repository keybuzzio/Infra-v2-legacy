#!/usr/bin/env bash
#
# 09_k3s_fix_coredns_v2.sh - Correction CoreDNS (Version Robuste)
#
# Problème: CoreDNS loop detected ou CrashLoopBackOff
# Solution: Recréer CoreDNS avec configuration K3s standard
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

# Trouver le premier master
declare -a K3S_MASTER_IPS=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "k3s" ]] && [[ "${SUBROLE}" == "master" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        K3S_MASTER_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#K3S_MASTER_IPS[@]} -lt 1 ]]; then
    log_error "Aucun master K3s trouvé"
    exit 1
fi

MASTER_IP="${K3S_MASTER_IPS[0]}"

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "/root/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i /root/.ssh/keybuzz_infra"
fi
SSH_KEY_OPTS="${SSH_KEY_OPTS} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "=============================================================="
echo " [KeyBuzz] Correction CoreDNS (Version Robuste)"
echo "=============================================================="
echo ""

log_info "Solution: Utiliser la configuration K3s standard pour CoreDNS"
echo ""

# Solution: Utiliser kubectl apply avec le manifeste K3s standard
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<'COREDNS_FIX'
set -euo pipefail

echo "=== Étape 1: Vérification état actuel ==="
kubectl get deployment coredns -n kube-system 2>/dev/null || echo "CoreDNS deployment non trouvé"
kubectl get pods -n kube-system -l k8s-app=kube-dns 2>/dev/null || echo "Aucun pod CoreDNS"
echo ""

echo "=== Étape 2: Suppression CoreDNS existant ==="
kubectl delete deployment coredns -n kube-system --ignore-not-found=true
kubectl delete serviceaccount coredns -n kube-system --ignore-not-found=true
kubectl delete clusterrole system:coredns --ignore-not-found=true
kubectl delete clusterrolebinding system:coredns --ignore-not-found=true
kubectl delete configmap coredns -n kube-system --ignore-not-found=true
sleep 5
echo "✓ Ressources CoreDNS supprimées"
echo ""

echo "=== Étape 3: Recréation CoreDNS avec manifeste K3s standard ==="
cat <<'EOF' | kubectl apply -f -
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
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30
        loop
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
EOF

echo "✓ CoreDNS recréé"
echo ""

echo "=== Étape 4: Attente que CoreDNS démarre (30 secondes) ==="
sleep 30

echo ""
echo "=== Étape 5: Vérification état CoreDNS ==="
kubectl get deployment coredns -n kube-system
echo ""
kubectl get pods -n kube-system -l k8s-app=kube-dns
echo ""

POD_NAME=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "${POD_NAME}" ]]; then
    echo "=== Logs CoreDNS (dernières 15 lignes) ==="
    kubectl logs -n kube-system "${POD_NAME}" --tail 15 2>&1 || echo "Impossible de lire les logs"
    echo ""
    
    STATUS=$(kubectl get pod -n kube-system "${POD_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "${STATUS}" == "Running" ]]; then
        echo "✓ CoreDNS est Running"
    else
        echo "⚠ CoreDNS status: ${STATUS}"
    fi
else
    echo "⚠ Aucun pod CoreDNS trouvé"
fi
COREDNS_FIX

echo ""
echo "=============================================================="
log_success "✅ Correction CoreDNS terminée"
echo "=============================================================="
echo ""

