# setup_ssh_agent.ps1 - Configure ssh-agent pour automatiser les connexions SSH
# Usage: .\setup_ssh_agent.ps1
# Ce script charge la clé SSH dans ssh-agent pour éviter de redemander le passphrase

$SSH_KEY = "$PSScriptRoot\..\..\SSH\keybuzz_infra"
$PASSPHRASE_FILE = "$PSScriptRoot\..\..\SSH\passphrase.txt"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Configuration ssh-agent pour automatisation SSH" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Vérifier la clé SSH
if (-not (Test-Path $SSH_KEY)) {
    Write-Host "❌ Clé SSH introuvable : $SSH_KEY" -ForegroundColor Red
    exit 1
}

# Démarrer ssh-agent si nécessaire
$sshAgentService = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($sshAgentService -and $sshAgentService.Status -ne 'Running') {
    Write-Host "🚀 Démarrage du service ssh-agent..." -ForegroundColor Yellow
    Start-Service ssh-agent
    Write-Host "✅ Service ssh-agent démarré" -ForegroundColor Green
} elseif (-not $sshAgentService) {
    Write-Host "⚠️  Service ssh-agent non disponible" -ForegroundColor Yellow
    Write-Host "   Utilisation de ssh-agent en mode utilisateur..." -ForegroundColor Yellow
}

# Vérifier si la clé est déjà chargée
$keysLoaded = ssh-add -l 2>&1
if ($LASTEXITCODE -eq 0 -and $keysLoaded -match "keybuzz_infra") {
    Write-Host "✅ Clé SSH déjà chargée dans ssh-agent" -ForegroundColor Green
    Write-Host ""
    exit 0
}

# Charger la clé dans ssh-agent
Write-Host "📝 Chargement de la clé SSH dans ssh-agent..." -ForegroundColor Yellow
Write-Host "   ⚠️  Vous devrez entrer le passphrase UNE SEULE FOIS" -ForegroundColor Yellow
Write-Host ""

# Essayer de lire le passphrase depuis le fichier si disponible
if (Test-Path $PASSPHRASE_FILE) {
    $passphrase = Get-Content $PASSPHRASE_FILE -Raw | ForEach-Object { $_.Trim() }
    Write-Host "✅ Passphrase lu depuis le fichier" -ForegroundColor Green
    Write-Host "   Chargement de la clé..." -ForegroundColor Yellow
    
    # Utiliser echo pour passer le passphrase à ssh-add
    # Note: Cette méthode peut ne pas fonctionner sur tous les systèmes
    $env:SSH_ASKPASS_REQUIRE = "never"
    $passphrase | ssh-add $SSH_KEY 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Clé SSH chargée avec succès dans ssh-agent" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Impossible de charger automatiquement la clé" -ForegroundColor Yellow
        Write-Host "   Chargement manuel..." -ForegroundColor Yellow
        ssh-add $SSH_KEY
    }
} else {
    Write-Host "⚠️  Fichier passphrase introuvable, chargement manuel..." -ForegroundColor Yellow
    ssh-add $SSH_KEY
}

Write-Host ""
Write-Host "✅ Configuration terminée" -ForegroundColor Green
Write-Host "   Vous pouvez maintenant vous connecter sans entrer le passphrase" -ForegroundColor Green
Write-Host ""

