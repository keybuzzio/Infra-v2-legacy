# Problème Module 7 - Cluster Galera ne démarre pas

**Date :** 2025-11-21

---

## 🔴 Problème Identifié

### Symptôme
- Le conteneur `maria-01` est en état **"Restarting"** (redémarre en boucle)
- Les ports 3306 ne sont pas accessibles sur les 3 nœuds
- Le cluster Galera est en cours de synchronisation mais ne se stabilise jamais
- ProxySQL ne peut pas se connecter car MariaDB n'est pas accessible

---

## 🔍 Causes Probables

1. **Problème de configuration Galera** : Configuration incorrecte dans `my.cnf`
2. **Problème de données** : Volume de données corrompu ou permissions incorrectes
3. **Problème réseau** : Les nœuds ne peuvent pas communiquer entre eux
4. **Problème de bootstrap** : Le nœud bootstrap ne démarre pas correctement
5. **Problème de credentials** : Mauvais mot de passe ou credentials

---

## 🔧 Actions de Diagnostic Nécessaires

1. ✅ Vérifier les logs du conteneur `maria-01` pour identifier l'erreur exacte
2. ⏳ Vérifier les permissions et l'état du volume de données
3. ⏳ Vérifier la configuration `my.cnf` générée
4. ⏳ Vérifier la connectivité réseau entre les nœuds (port 4567)
5. ⏳ Vérifier que les credentials sont corrects

---

## 📋 Prochaines Étapes

1. Analyser les logs pour identifier l'erreur exacte
2. Corriger la configuration ou redémarrer proprement le cluster
3. Relancer les tests une fois le cluster stable

---

**Note :** Le problème semble être au niveau du déploiement du cluster Galera lui-même, pas au niveau des tests ProxySQL.

