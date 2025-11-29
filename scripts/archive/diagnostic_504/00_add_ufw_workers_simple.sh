#!/usr/bin/env bash
# Script simple pour ajouter les règles UFW sur tous les workers
# À exécuter depuis install-01 une fois l'accès SSH configuré

echo "Ajout des règles UFW sur tous les workers K3s..."
echo ""

# Workers avec leurs IPs privées
workers=(
    "10.0.0.110"  # worker-01
    "10.0.0.111"  # worker-02
    "10.0.0.112"  # worker-03 (POD KEYBUZZ ICI)
    "10.0.0.113"  # worker-04
    "10.0.0.114"  # worker-05
)

for ip in "${workers[@]}"; do
    echo "Traitement $ip..."
    ssh root@"$ip" "ufw allow from 10.42.0.0/16 to any comment 'K3s pods network' && \
                    ufw allow from 10.43.0.0/16 to any comment 'K3s services network' && \
                    ufw allow 8472/udp comment 'K3s flannel VXLAN' && \
                    ufw allow 10250/tcp comment 'K3s kubelet' && \
                    echo '✅ Règles ajoutées sur $ip'" || echo "❌ Échec sur $ip"
    echo ""
done

echo "Terminé !"

