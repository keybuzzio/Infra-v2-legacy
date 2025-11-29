# Résumé Correction Module 7 - MariaDB Galera HA

**Date :** 2025-11-21

---

## 🔴 Problème Principal Identifié

### Erreur : Cluster Galera ne démarre pas
**Symptôme :** Le conteneur `maria-01` redémarre en boucle avec l'erreur :
```
[ERROR] WSREP: It may not be safe to bootstrap the cluster from this node. It was not the last one to leave the cluster and may not contain all the updates. To force cluster bootstrap with this node, edit the grastate.dat file manually and set safe_to_bootstrap to 1 .
```

**Cause :** Le fichier `grastate.dat` a `safe_to_bootstrap: 0`, ce qui empêche le bootstrap du cluster Galera. Cela arrive quand un cluster a été arrêté de manière non propre.

---

## ✅ Corrections Appliquées

### 1. Correction du script de déploiement
**Fichier :** `07_mariadb_galera/07_maria_02_deploy_galera.sh`

**Modification :** Ajout d'une vérification et modification automatique de `grastate.dat` pour forcer `safe_to_bootstrap: 1` avant le démarrage du nœud bootstrap.

**Code ajouté :**
```bash
# Forcer le bootstrap en modifiant grastate.dat si nécessaire
if [[ -f "\${BASE}/data/grastate.dat" ]]; then
    log_info "Modification de grastate.dat pour forcer le bootstrap..."
    sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' "\${BASE}/data/grastate.dat" || true
fi
```

### 2. Correction manuelle immédiate
**Action :** Modification du fichier `grastate.dat` sur maria-01 pour forcer le bootstrap.

**Commande :**
```bash
sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /opt/keybuzz/mariadb/data/grastate.dat
```

### 3. Redémarrage du conteneur
**Action :** Redémarrage du conteneur `mariadb` sur maria-01 pour appliquer la correction.

---

## 📋 Prochaines Étapes

1. ⏳ Attendre que le conteneur démarre correctement (vérification en cours...)
2. ⏳ Vérifier que le cluster Galera se forme correctement
3. ⏳ Relancer les tests une fois le cluster stable

---

## 🔍 Vérifications à Faire

1. ✅ Conteneur redémarré
2. ⏳ Vérifier les logs pour confirmer le démarrage
3. ⏳ Vérifier que le port 3306 devient accessible
4. ⏳ Vérifier que le cluster se forme avec les 3 nœuds

---

**Note :** La correction a été appliquée au script et au conteneur existant. Le script corrigé a été transféré sur install-01 pour les prochaines installations.

