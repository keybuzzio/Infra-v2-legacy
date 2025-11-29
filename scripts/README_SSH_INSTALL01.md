# Guide d'utilisation SSH pour install-01

## Script Principal

**Utiliser le script : `ssh_install01.ps1`**

Ce script utilise **Pageant + plink** pour une connexion fiable et automatique.

## Prérequis

1. **PuTTY doit etre installe** (plink doit etre disponible dans le PATH)
2. **Pageant doit etre actif** avec la cle SSH chargee

## Configuration initiale (une seule fois)

### Etape 1 : Demarrer Pageant

1. Ouvrir Pageant depuis le menu Demarrer
2. Verifier que l'icone Pageant apparait dans la barre des taches

### Etape 2 : Charger la cle SSH dans Pageant

1. Clic droit sur l'icone Pageant dans la barre des taches
2. Selectionner "Add Key"
3. Choisir le fichier de cle SSH (ex: `SSH\keybuzz_infra` ou le fichier .ppk correspondant)
4. Entrer le passphrase de la cle quand demande

**Note:** Une fois la cle chargee dans Pageant, vous n'aurez plus besoin d'entrer le passphrase a chaque connexion (tant que Pageant est actif).

## Utilisation

### Executer une commande sur install-01

```powershell
cd "C:\Users\ludov\Mon Drive\keybuzzio\Infra\scripts"
.\ssh_install01.ps1 "echo 'Test' && hostname && whoami"
```

### Session interactive SSH

```powershell
.\ssh_install01.ps1
```

### Exemples de commandes

```powershell
# Verifier l'heure du serveur
.\ssh_install01.ps1 "date"

# Verifier l'espace disque
.\ssh_install01.ps1 "df -h"

# Verifier les processus
.\ssh_install01.ps1 "ps aux | head -20"

# Executer plusieurs commandes
.\ssh_install01.ps1 "hostname && whoami && date && uptime"
```

## Avantages de cette methode

- **Aucune saisie de passphrase necessaire** (Pageant la gere automatiquement)
- **Connexion automatique et fiable**
- **Compatible avec tous les scripts PowerShell**
- **Fonctionne meme avec des caracteres speciaux Windows**

## Depannage

### Erreur : "Plink n'est pas disponible"

Installer PuTTY depuis : https://www.putty.org/

### Erreur : "Pageant n'est pas actif"

1. Demarrer Pageant depuis le menu Demarrer
2. Charger la cle SSH dans Pageant (voir Configuration initiale ci-dessus)

### La connexion echoue

1. Verifier que Pageant est actif : l'icone doit etre visible dans la barre des taches
2. Verifier que la cle est bien chargee dans Pageant : clic droit sur l'icone -> voir les cles chargees
3. Verifier que la cle correspond bien au serveur install-01

## Scripts alternatifs

- `connect_to_install01.ps1` - Version avec SSH direct (demande le passphrase manuellement)
- `connect_install01_pageant.ps1` - Version avec affichage detaille

**RECOMMANDE : Utiliser `ssh_install01.ps1` pour toutes les connexions**

