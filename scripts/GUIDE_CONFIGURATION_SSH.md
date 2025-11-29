# Guide de Configuration SSH pour Automatisation

## Solution Simple : Configuration ssh-agent une seule fois

### Méthode 1 : Configuration manuelle (Recommandée)

1. **Démarrer ssh-agent** :
```powershell
Start-Service ssh-agent
```

2. **Charger la clé (une seule fois)** :
```powershell
cd "C:\Users\ludov\Mon Drive\keybuzzio\Infra\scripts"
ssh-add "..\..\SSH\keybuzz_infra"
# Entrez le passphrase quand demandé
```

3. **Vérifier que la clé est chargée** :
```powershell
ssh-add -l
```

4. **Maintenant vous pouvez exécuter les tests sans entrer le passphrase** :
```powershell
.\exec_tests_install01.ps1
```

### Méthode 2 : Via Git Bash (si disponible)

Si vous avez Git Bash installé :

```bash
cd "/c/Users/ludov/Mon Drive/keybuzzio/Infra/scripts"
eval $(ssh-agent)
ssh-add "../../SSH/keybuzz_infra"
# Entrez le passphrase quand demandé

# Ensuite exécutez les tests
bash exec_on_install01.sh "cd /opt/keybuzz-installer/scripts && ./00_test_complet_infrastructure_haproxy01.sh"
```

## Important

Une fois la clé chargée dans ssh-agent, elle reste chargée jusqu'à :
- Fermeture de la session PowerShell
- Redémarrage du service ssh-agent
- Suppression manuelle avec `ssh-add -d`

## Scripts Disponibles

- `exec_tests_install01.ps1` - Exécute les tests sur install-01 (nécessite ssh-agent configuré)
- `00_test_complet_infrastructure_haproxy01.sh` - Script de test complet (doit être sur install-01)

