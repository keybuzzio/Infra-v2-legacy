# 🔑 Ajout d'une Nouvelle Clé SSH sur install-01

## 📋 Instructions

Une nouvelle clé SSH a été générée. Voici comment l'ajouter sur install-01.

### Méthode 1 : Depuis votre machine (si vous avez encore accès)

```bash
# Copier la clé publique sur install-01
cat ~/.ssh/keybuzz_install01_*.pub | ssh root@install-01 'cat >> ~/.ssh/authorized_keys'
```

### Méthode 2 : Depuis install-01 directement

Si vous êtes connecté sur install-01, exécutez :

```bash
# 1. Afficher la clé publique (copiez-la depuis votre machine Windows)
# La clé publique se trouve dans : C:\Users\ludov\.ssh\keybuzz_install01_YYYYMMDD_HHMMSS.pub

# 2. Sur install-01, ajoutez-la :
echo "VOTRE_CLE_PUBLIQUE_ICI" >> ~/.ssh/authorized_keys

# 3. Vérifiez les permissions
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
```

### Méthode 3 : Via un fichier temporaire

```bash
# Sur votre machine Windows, créez un fichier avec la clé publique
# Puis sur install-01 :
cat > /tmp/new_key.pub <<'EOF'
VOTRE_CLE_PUBLIQUE_ICI
EOF

cat /tmp/new_key.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
rm /tmp/new_key.pub
```

## 🔍 Vérification

Après avoir ajouté la clé, testez la connexion :

```bash
# Depuis votre machine Windows
ssh -i "C:\Users\ludov\.ssh\keybuzz_install01_*.pub" root@install-01 "echo 'Connexion OK'"
```

## 📝 Emplacement des Clés

- **Clé privée** : `C:\Users\ludov\.ssh\keybuzz_install01_YYYYMMDD_HHMMSS`
- **Clé publique** : `C:\Users\ludov\.ssh\keybuzz_install01_YYYYMMDD_HHMMSS.pub`

## ⚠️ Important

- Ne partagez JAMAIS la clé privée
- Seule la clé publique doit être ajoutée sur install-01
- La clé privée reste sur votre machine Windows


