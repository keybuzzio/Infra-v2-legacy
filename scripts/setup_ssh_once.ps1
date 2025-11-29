# setup_ssh_once.ps1 - Configuration SSH une seule fois
# Usage: .\setup_ssh_once.ps1
#
# Ce script configure ssh-agent et charge la clé SSH
# Vous devrez entrer le passphrase UNE SEULE FOIS
# Ensuite, vous pourrez utiliser connect_install01_quick.ps1 sans passphrase

$SSH_KEY_PATH = "$PSScriptRoot\..\..\SSH\keybuzz_infra"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Configuration SSH pour install-01" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Vérifier que la clé existe
if (-not (Test-Path $SSH_KEY_PATH)) {
    Write-Host "❌ Clé SSH introuvable : $SSH_KEY_PATH" -ForegroundColor Red
    exit 1
}

# Démarrer ssh-agent
$agent = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($agent) {
    if ($agent.Status -ne 'Running') {
        Write-Host "🚀 Démarrage du service ssh-agent..." -ForegroundColor Yellow
        Set-Service -Name ssh-agent -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service ssh-agent
        Start-Sleep -Seconds 2
        Write-Host "✅ Service ssh-agent démarré" -ForegroundColor Green
    } else {
        Write-Host "✅ Service ssh-agent déjà actif" -ForegroundColor Green
    }
} else {
    Write-Host "⚠️  Service ssh-agent non disponible" -ForegroundColor Yellow
    Write-Host "   Vous devrez peut-être installer OpenSSH pour Windows" -ForegroundColor Yellow
}

# Vérifier si la clé est déjà chargée
Write-Host ""
Write-Host "Vérification des clés chargées..." -ForegroundColor Yellow
$keys = ssh-add -l 2>&1
if ($LASTEXITCODE -eq 0 -and $keys -notmatch "The agent has no identities") {
    Write-Host "✅ Des clés sont déjà chargées dans ssh-agent" -ForegroundColor Green
    Write-Host ""
    Write-Host "Clés actuellement chargées :" -ForegroundColor Cyan
    ssh-add -l
    Write-Host ""
    $response = Read-Host "Voulez-vous charger la clé keybuzz_infra quand même ? (O/N)"
    if ($response -ne "O" -and $response -ne "o") {
        Write-Host "Configuration annulée" -ForegroundColor Yellow
        exit 0
    }
}

# Charger la clé
Write-Host ""
Write-Host "📝 Chargement de la clé SSH..." -ForegroundColor Yellow
Write-Host "   Vous devrez entrer le passphrase ci-dessous :" -ForegroundColor Cyan
Write-Host ""

ssh-add $SSH_KEY_PATH

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ Clé SSH chargée avec succès !" -ForegroundColor Green
    Write-Host ""
    Write-Host "Vous pouvez maintenant utiliser :" -ForegroundColor Cyan
    Write-Host "  .\connect_install01_quick.ps1" -ForegroundColor White
    Write-Host "  .\connect_install01_quick.ps1 'commande'" -ForegroundColor White
    Write-Host ""
    Write-Host "La clé restera chargée jusqu'à la fermeture de cette session PowerShell" -ForegroundColor Gray
    Write-Host "ou jusqu'au redémarrage de ssh-agent" -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "❌ Échec du chargement de la clé" -ForegroundColor Red
    Write-Host "   Verifiez que le passphrase est correct" -ForegroundColor Yellow
    exit 1
}


