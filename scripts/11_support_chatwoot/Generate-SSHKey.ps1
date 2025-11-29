# Script PowerShell pour générer une nouvelle clé SSH

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$keyName = "keybuzz_install01_$timestamp"
$sshDir = "$env:USERPROFILE\.ssh"
$privateKeyPath = Join-Path $sshDir $keyName
$publicKeyPath = "$privateKeyPath.pub"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " [KeyBuzz] Génération Nouvelle Clé SSH" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Créer le répertoire .ssh s'il n'existe pas
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

Write-Host "Génération de la clé SSH: $keyName" -ForegroundColor Yellow
Write-Host ""

# Générer la clé
$result = & ssh-keygen -t ed25519 -f $privateKeyPath -N '""' -C "keybuzz-install01-$timestamp" 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Clé SSH générée avec succès" -ForegroundColor Green
    Write-Host ""
    
    # Lire la clé publique
    $publicKey = Get-Content $publicKeyPath -Raw
    
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host " CLÉ PUBLIQUE (à copier sur install-01)" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host $publicKey.Trim() -ForegroundColor Green
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Commande pour ajouter sur install-01
    Write-Host "COMMANDE POUR AJOUTER SUR install-01:" -ForegroundColor Yellow
    Write-Host "-" * 60 -ForegroundColor Gray
    Write-Host ""
    Write-Host "Depuis votre machine Windows:" -ForegroundColor White
    Write-Host "  Get-Content `"$publicKeyPath`" | ssh root@install-01 'cat >> ~/.ssh/authorized_keys'" -ForegroundColor Green
    Write-Host ""
    Write-Host "OU depuis install-01 (si vous êtes connecté):" -ForegroundColor White
    Write-Host "  echo '$($publicKey.Trim())' >> ~/.ssh/authorized_keys" -ForegroundColor Green
    Write-Host "  chmod 600 ~/.ssh/authorized_keys" -ForegroundColor Green
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Clé privée: $privateKeyPath" -ForegroundColor White
    Write-Host "Clé publique: $publicKeyPath" -ForegroundColor White
    Write-Host ""
    Write-Host "Pour utiliser cette clé:" -ForegroundColor Yellow
    Write-Host "  ssh -i `"$privateKeyPath`" root@install-01" -ForegroundColor Green
    Write-Host ""
    
    # Sauvegarder la clé publique dans un fichier pour référence
    $infoFile = Join-Path $PSScriptRoot "SSH_KEY_INFO_$timestamp.txt"
    @"
Clé SSH générée le $(Get-Date)

Clé privée: $privateKeyPath
Clé publique: $publicKeyPath

Clé publique:
$($publicKey.Trim())

Commande pour ajouter sur install-01:
echo '$($publicKey.Trim())' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

Pour utiliser:
ssh -i "$privateKeyPath" root@install-01
"@ | Out-File -FilePath $infoFile -Encoding UTF8
    
    Write-Host "Informations sauvegardées dans: $infoFile" -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host "❌ Erreur lors de la génération de la clé" -ForegroundColor Red
    Write-Host $result
    exit 1
}


