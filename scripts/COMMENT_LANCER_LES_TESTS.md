# Comment Lancer les Tests - Guide Simple

## Étape par étape

### 1. Ouvrez PowerShell dans le répertoire des scripts

```powershell
cd "C:\Users\ludov\Mon Drive\keybuzzio\Infra\scripts"
```

### 2. Lancez le script de test

```powershell
.\LANCER_LES_TESTS.ps1
```

### 3. Quand vous voyez "Enter passphrase for key..."

**C'EST MAINTENANT QUE VOUS DEVEZ ENTRER LE PASSPHRASE :**

1. **Tapez votre passphrase** (les caractères ne s'afficheront PAS à l'écran, c'est normal pour la sécurité)
2. **Appuyez sur Entrée**

**IMPORTANT** : 
- Le passphrase est invisible quand vous le tapez (c'est normal)
- Tapez-le quand même, puis appuyez sur Entrée
- Si vous faites une erreur, appuyez sur Entrée quand même et réessayez

### 4. La connexion va s'établir

Une fois le passphrase accepté, vous verrez :
- La connexion SSH s'établir
- Les tests démarrer automatiquement
- Les résultats s'afficher

## Alternative : Commande directe

Si vous préférez, vous pouvez aussi utiliser directement :

```powershell
$SSH_KEY = Resolve-Path "..\..\SSH\keybuzz_infra"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new root@91.98.128.153 "cd /opt/keybuzz-installer/scripts && ./00_test_complet_infrastructure_haproxy01.sh"
```

Puis entrez le passphrase quand demandé.

## En cas de problème

Si vous ne voyez pas "Enter passphrase for key..." :
- Le script attend peut-être votre saisie
- Essayez de taper le passphrase quand même et appuyez sur Entrée
- Si ça ne fonctionne pas, appuyez sur Ctrl+C pour annuler et réessayez

