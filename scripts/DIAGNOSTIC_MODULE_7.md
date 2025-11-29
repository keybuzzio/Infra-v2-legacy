# Diagnostic et Correction Module 7 - MariaDB Galera HA

**Date :** 2025-11-21

---

## 🔍 Problèmes Identifiés

### 1. Erreur "Received malformed packet"
**Symptôme :** Erreur `ERROR 2027 (HY000): Received malformed packet` lors des tests d'écriture/lecture via ProxySQL.

**Causes identifiées :**
1. Utilisation de heredoc SQL multi-lignes (`<<SQL`) qui peut causer des problèmes de packet avec ProxySQL
2. Cluster Galera en cours de synchronisation lors des tests
3. Base de données peut ne pas exister au moment des tests
4. Pas de gestion d'erreur pour les variables non définies dans le heredoc
5. Pas d'attente pour que le cluster soit prêt

---

## ✅ Corrections Appliquées

### Correction 1 : Remplacement heredoc SQL multi-lignes
**Problème :** Le heredoc SQL multi-lignes peut causer des problèmes de packet avec ProxySQL.

**Solution :** Remplacement par une commande SQL en une seule ligne pour la création de table.

**Fichier :** `07_mariadb_galera/07_maria_04_tests.sh` ligne 244

---

### Correction 2 : Gestion des variables non définies
**Problème :** Variables non définies dans le heredoc causaient des erreurs.

**Solution :** Ajout de `set +u` / `set -u` pour gérer les variables non définies.

**Fichier :** `07_mariadb_galera/07_maria_04_tests.sh` lignes 196-198, 243-245

---

### Correction 3 : Attente de stabilisation du cluster
**Problème :** Les tests étaient exécutés avant que le cluster Galera soit prêt.

**Solution :** 
- Ajout d'une attente de 30 secondes avant les tests ProxySQL
- Ajout d'une boucle de retry (10 tentatives, 3 secondes entre chaque) pour attendre que ProxySQL soit prêt

**Fichier :** `07_mariadb_galera/07_maria_04_tests.sh` ligne 195

---

### Correction 4 : Vérification et création de la base de données
**Problème :** La base de données peut ne pas exister au moment des tests.

**Solution :** Vérification de l'existence de la base et création si nécessaire avant les tests.

**Fichier :** `07_mariadb_galera/07_maria_04_tests.sh` lignes 207-210

---

### Correction 5 : Amélioration de la gestion d'erreur
**Problème :** Messages d'erreur peu informatifs.

**Solution :** 
- Affichage des messages d'erreur détaillés
- Meilleure gestion des erreurs avec codes de sortie appropriés

**Fichier :** `07_mariadb_galera/07_maria_04_tests.sh` lignes 250-252

---

### Correction 6 : Détection SSH pour IP internes
**Problème :** Le script cherchait une clé SSH alors qu'il n'en a pas besoin depuis install-01 pour les IP internes.

**Solution :** Utilisation directe des options SSH sans clé pour les connexions internes.

**Fichier :** `07_mariadb_galera/07_maria_04_tests.sh` lignes 61-68

---

## 📋 Résumé des Modifications

1. ✅ Remplacement heredoc SQL multi-lignes par commande SQL en une ligne
2. ✅ Ajout de `set +u` / `set -u` pour gestion des variables
3. ✅ Ajout d'attente de 30 secondes + boucle de retry pour ProxySQL
4. ✅ Vérification et création automatique de la base de données
5. ✅ Amélioration des messages d'erreur
6. ✅ Correction de la détection SSH pour IP internes

---

## 🔧 Prochaines Étapes

1. Relancer les tests du Module 7
2. Vérifier que le cluster Galera est stable
3. Valider que ProxySQL fonctionne correctement

---

**Note :** Toutes les corrections ont été appliquées et le script a été transféré sur install-01.

