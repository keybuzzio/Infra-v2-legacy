# Corrections et Erreurs - Installation KeyBuzz

**Dernière mise à jour :** 2025-11-21

---

## 📋 Liste des Corrections

### ✅ Correction 15 : Cluster Galera ne démarre pas - safe_to_bootstrap: 0
**Problème :** Le conteneur `maria-01` redémarre en boucle avec l'erreur :
```
[ERROR] WSREP: It may not be safe to bootstrap the cluster from this node. It was not the last one to leave the cluster and may not contain all the updates. To force cluster bootstrap with this node, edit the grastate.dat file manually and set safe_to_bootstrap to 1 .
```

**Cause :** Le fichier `grastate.dat` a `safe_to_bootstrap: 0`, ce qui empêche le bootstrap du cluster Galera. Cela arrive quand un cluster a été arrêté de manière non propre.

**Solution :** Modification automatique de `grastate.dat` pour forcer `safe_to_bootstrap: 1` avant le démarrage du nœud bootstrap.

**Fichier modifié :**
- `07_mariadb_galera/07_maria_02_deploy_galera.sh`

**Date :** 2025-11-21

**Changement spécifique :**
- Ajout d'une vérification et modification de `grastate.dat` avant le démarrage du conteneur bootstrap (lignes 181-185)

---

### ✅ Correction 16 : Utilisateur erpnext non créé dans MariaDB
**Problème :** L'utilisateur `erpnext` n'était pas créé dans MariaDB, causant des erreurs "Access denied" lors des connexions via ProxySQL.

**Symptômes :**
- ProxySQL ne pouvait pas se connecter à MariaDB
- Erreur : "Access denied for user 'erpnext'@'10.0.0.173'"
- Les tests de connexion via ProxySQL échouaient

**Cause :** Le script de déploiement Galera créait l'utilisateur avec `CREATE USER IF NOT EXISTS`, mais l'utilisateur n'était pas réellement créé (probablement problème d'expansion de variables dans le heredoc SQL).

**Solution :**
1. Suppression de l'utilisateur existant avant création (pour éviter les conflits)
2. Utilisation de `CREATE USER` au lieu de `CREATE USER IF NOT EXISTS` pour forcer la création
3. Ajout d'une vérification que l'utilisateur a bien été créé après la création

**Fichier modifié :**
- `07_mariadb_galera/07_maria_02_deploy_galera.sh`

**Date :** 2025-11-21

**Changement spécifique :**
- Lignes 328-350 : Amélioration de la création de l'utilisateur avec suppression préalable et vérification

**Résultat :** ✅ Tous les tests passent maintenant
- ✅ Connexion ProxySQL réussie
- ✅ Accès à la base erpnext réussi
- ✅ Écriture/lecture réussie

---

## 📝 Notes Importantes

1. **Connexions SSH depuis install-01 :** Depuis install-01, les connexions SSH vers les autres serveurs avec les IP internes 10.0.0.x ne nécessitent PAS de clé SSH. Utiliser simplement `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null`.

2. **Mode non-interactif :** Tous les scripts doivent supporter le flag `--yes` pour l'installation automatique.

3. **Credentials :** Les scripts de credentials doivent utiliser automatiquement les fichiers existants en mode `--yes`.

4. **ProxySQL et heredoc SQL :** Éviter les heredoc SQL multi-lignes avec ProxySQL, utiliser des commandes SQL en une seule ligne pour éviter les problèmes de "malformed packet".

5. **Galera Bootstrap :** Si un cluster Galera a été arrêté de manière non propre, il faut forcer le bootstrap en modifiant `grastate.dat` pour mettre `safe_to_bootstrap: 1`.

6. **Création utilisateur MariaDB :** Toujours supprimer l'utilisateur existant avant de le recréer pour éviter les problèmes de permissions ou de mot de passe incorrect.

---

**Note :** Ce document est mis à jour au fur et à mesure des corrections.
