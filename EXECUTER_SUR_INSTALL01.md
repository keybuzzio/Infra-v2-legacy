# Exécuter des scripts sur install-01

## Méthode 1 : Via le terminal Cursor (Recommandé)

Puisque vous êtes déjà connecté via Cursor Remote SSH :

1. **Ouvrir un terminal dans Cursor** (Terminal → New Terminal)
2. **Le terminal est déjà connecté à install-01**
3. **Exécuter directement les commandes** :

```bash
# Exemple : Identification du serveur
hostname && whoami && ip addr show | grep "inet 10.0.0"
```

## Méthode 2 : Via SSH depuis PowerShell

Si vous voulez exécuter depuis PowerShell :

```powershell
# Avec votre clé SSH
ssh -i C:\Users\ludov\.ssh\keybuzz_infra root@91.98.128.153 "commande"

# Ou si configuré dans ~/.ssh/config
ssh install-01 "commande"
```

## Méthode 3 : Scripts automatiques

J'ai créé des scripts pour automatiser :

### Script PowerShell : `scripts/ssh_exec.ps1`

```powershell
# Exécuter une commande
.\scripts\ssh_exec.ps1 "hostname && whoami"

# Exécuter un script distant
.\scripts\ssh_exec.ps1 "bash /opt/keybuzz-installer/scripts/identify_server.sh"
```

### Script Bash : `scripts/run_on_install01.sh`

```bash
# Transférer et exécuter un script local
./scripts/run_on_install01.sh scripts/identify_server.sh

# Exécuter une commande
./scripts/run_on_install01.sh "hostname && whoami"
```

## Méthode 4 : Utiliser le terminal Cursor directement

**C'est la méthode la plus simple** puisque vous êtes déjà connecté :

1. Dans Cursor, ouvrir un terminal (Terminal → New Terminal)
2. Le terminal est automatiquement sur install-01
3. Exécuter les commandes directement

## Commandes utiles pour tester

```bash
# Identification complète
hostname && whoami && ip addr show | grep "inet 10.0.0"

# Vérifier Docker
docker --version

# Vérifier Git
git --version

# Vérifier le swap
swapon --summary

# Lister les répertoires
ls -la /opt/
```

## Prochaines étapes

Une fois que vous pouvez exécuter des commandes sur install-01, je pourrai :

1. ✅ Créer les scripts d'installation
2. ✅ Les transférer sur install-01
3. ✅ Les exécuter automatiquement
4. ✅ Vérifier les résultats

**Recommandation** : Utilisez le terminal Cursor directement - c'est le plus simple !


