#!/usr/bin/env bash
# Script de test manuel pour RabbitMQ HA

set -euo pipefail

source /opt/keybuzz-installer-v2/credentials/rabbitmq.env

echo "=============================================================="
echo " Tests RabbitMQ HA - Module 5"
echo "=============================================================="
echo ""

echo "=== TEST 1: Connectivité RabbitMQ Directe ==="
echo "queue-01:"
ssh root@10.0.0.126 "docker exec rabbitmq rabbitmq-diagnostics ping" || echo "❌ Échec"
echo "queue-02:"
ssh root@10.0.0.127 "docker exec rabbitmq rabbitmq-diagnostics ping" || echo "❌ Échec"
echo "queue-03:"
ssh root@10.0.0.128 "docker exec rabbitmq rabbitmq-diagnostics ping" || echo "❌ Échec"
echo ""

echo "=== TEST 2: Statut du Cluster ==="
echo "Cluster status:"
ssh root@10.0.0.126 "docker exec rabbitmq rabbitmqctl cluster_status" || echo "❌ Échec"
echo ""

echo "=== TEST 3: Liste des Nœuds ==="
echo "Nœuds du cluster:"
ssh root@10.0.0.126 "docker exec rabbitmq rabbitmqctl list_nodes" || echo "❌ Échec"
echo ""

echo "=== TEST 4: Utilisateurs ==="
echo "Utilisateurs configurés:"
ssh root@10.0.0.126 "docker exec rabbitmq rabbitmqctl list_users" || echo "❌ Échec"
echo ""

echo "=== TEST 5: HAProxy ==="
echo "haproxy-01:"
ssh root@10.0.0.11 "docker ps | grep haproxy-rabbitmq || echo Pas de HAProxy" || echo "❌ Échec"
echo "haproxy-02:"
ssh root@10.0.0.12 "docker ps | grep haproxy-rabbitmq || echo Pas de HAProxy" || echo "❌ Échec"
echo ""

echo "=== TEST 6: Port HAProxy ==="
echo "haproxy-01 port 5672:"
ssh root@10.0.0.11 "docker exec haproxy-rabbitmq sh -c 'nc -z 127.0.0.1 5672 && echo Port ouvert || echo Port fermé'" || echo "⚠️  Test port (nc peut ne pas être disponible)"
echo "haproxy-02 port 5672:"
ssh root@10.0.0.12 "docker exec haproxy-rabbitmq sh -c 'nc -z 127.0.0.1 5672 && echo Port ouvert || echo Port fermé'" || echo "⚠️  Test port (nc peut ne pas être disponible)"
echo ""

echo "=============================================================="
echo " Tests terminés"
echo "=============================================================="

