#!/usr/bin/env bash
# Script de test manuel pour MinIO HA

set -euo pipefail

source /opt/keybuzz-installer-v2/credentials/minio.env

echo "=============================================================="
echo " Tests MinIO HA - Module 6"
echo "=============================================================="
echo ""

echo "=== TEST 1: Connectivité MinIO Directe ==="
echo "minio-01:"
ssh root@10.0.0.134 "docker ps | grep minio || echo Pas de MinIO" || echo "❌ Échec"
echo "minio-02:"
ssh root@10.0.0.131 "docker ps | grep minio || echo Pas de MinIO" || echo "❌ Échec"
echo "minio-03:"
ssh root@10.0.0.132 "docker ps | grep minio || echo Pas de MinIO" || echo "❌ Échec"
echo ""

echo "=== TEST 2: Ports MinIO ==="
echo "minio-01 port 9000:"
ssh root@10.0.0.134 "docker exec minio sh -c 'nc -z 127.0.0.1 9000 && echo Port ouvert || echo Port fermé'" || echo "⚠️  Test port (nc peut ne pas être disponible)"
echo "minio-02 port 9000:"
ssh root@10.0.0.131 "docker exec minio sh -c 'nc -z 127.0.0.1 9000 && echo Port ouvert || echo Port fermé'" || echo "⚠️  Test port (nc peut ne pas être disponible)"
echo "minio-03 port 9000:"
ssh root@10.0.0.132 "docker exec minio sh -c 'nc -z 127.0.0.1 9000 && echo Port ouvert || echo Port fermé'" || echo "⚠️  Test port (nc peut ne pas être disponible)"
echo ""

echo "=== TEST 3: Statut du Cluster MinIO ==="
echo "Cluster status (minio-01):"
ssh root@10.0.0.134 "docker exec minio mc admin info local 2>&1 | head -20 || echo 'mc non disponible ou cluster en cours d\'initialisation'" || echo "❌ Échec"
echo ""

echo "=== TEST 4: Volumes Montés ==="
echo "minio-01:"
ssh root@10.0.0.134 "df -h | grep /opt/keybuzz/minio/data || echo Volume non monté" || echo "❌ Échec"
echo "minio-02:"
ssh root@10.0.0.131 "df -h | grep /opt/keybuzz/minio/data || echo Volume non monté" || echo "❌ Échec"
echo "minio-03:"
ssh root@10.0.0.132 "df -h | grep /opt/keybuzz/minio/data || echo Volume non monté" || echo "❌ Échec"
echo ""

echo "=== TEST 5: Logs MinIO (dernières lignes) ==="
echo "minio-01:"
ssh root@10.0.0.134 "docker logs minio 2>&1 | tail -5 || echo Pas de logs" || echo "❌ Échec"
echo ""

echo "=============================================================="
echo " Tests terminés"
echo "=============================================================="

