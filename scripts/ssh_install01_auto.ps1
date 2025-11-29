# ssh_install01_auto.ps1 - Connexion SSH automatique à install-01
# Usage: .\ssh_install01_auto.ps1 "commande"
#        .\ssh_install01_auto.ps1  # Session interactive
#
# Ce script gère automatiquement ssh-agent et charge la clé SSH
# Le passphrase sera demandé UNE SEULE FOIS par session PowerShell

param(
    [Parameter(Mandatory=$false)]
    [string]$Command = ""
)

# Configuration
$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$SSH_KEY_PATH = "$PSScriptRoot\..\..\SSH\keybuzz_infra"

# Vérifier que la clé existe
if (-not (Test-Path $SSH_KEY_PATH)) {
    Write-Host "❌ Clé SSH introuvable : $SSH_KEY_PATH" -ForegroundColor Red
    exit 1
}

# Fonction pour vérifier si ssh-agent est actif et la clé chargée
function Test-SshKeyInAgent {
    $result = ssh-add -l 2>&1
    if ($LASTEXITCODE -eq 0) {
        # Vérifier si une clé est chargée (peu importe laquelle, on vérifiera après)
        return $true
    }
    return $false
}

# Fonction pour charger la clé avec le passphrase
function Add-SshKeyToAgent {
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  Configuration de la connexion SSH" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "📝 Chargement de la clé SSH dans ssh-agent..." -ForegroundColor Yellow
    Write-Host "   Vous devrez entrer le passphrase UNE SEULE FOIS" -ForegroundColor Yellow
    Write-Host ""
    
    # Démarrer ssh-agent si nécessaire
    $agent = Get-Service ssh-agent -ErrorAction SilentlyContinue
    if ($agent) {
        if ($agent.Status -ne 'Running') {
            Write-Host "🚀 Démarrage du service ssh-agent..." -ForegroundColor Yellow
            Start-Service ssh-agent
            Start-Sleep -Seconds 2
        }
    }
    
    # Méthode pour Windows : utiliser un script temporaire avec expect-like
    # Créer un script PowerShell qui simule l'entrée du passphrase
    $tempScript = Join-Path $env:TEMP "ssh-add-keybuzz.ps1"
    
    # Utiliser une méthode avec echo et pipe (peut ne pas fonctionner sur tous les systèmes)
    # La méthode la plus fiable est de demander manuellement
    Write-Host "   Entrez le passphrase ci-dessous :" -ForegroundColor Cyan
    Write-Host ""
    
    # Méthode principale : ssh-add manuel (le plus fiable sur Windows)
    Write-Host "   Passphrase requis - entrez-le maintenant :" -ForegroundColor Cyan
    ssh-add $SSH_KEY_PATH
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Clé SSH chargée avec succès" -ForegroundColor Green
        return $true
    } else {
        Write-Host "❌ Échec du chargement de la clé" -ForegroundColor Red
        return $false
    }
}

# Vérifier si la clé est déjà chargée
$keyLoaded = Test-SshKeyInAgent

if (-not $keyLoaded) {
    if (-not (Add-SshKeyToAgent)) {
        Write-Host ""
        Write-Host "❌ Impossible de charger la clé SSH" -ForegroundColor Red
        Write-Host "   Vous pouvez essayer manuellement :" -ForegroundColor Yellow
        Write-Host "   ssh-add $SSH_KEY_PATH" -ForegroundColor Gray
        exit 1
    }
} else {
    Write-Host "✅ Clé SSH déjà disponible dans ssh-agent" -ForegroundColor Green
}

# Se connecter au serveur
Write-Host ""
Write-Host "🔌 Connexion à install-01 ($INSTALL_01_IP)..." -ForegroundColor Cyan
Write-Host ""

if ($Command) {
    # Exécuter une commande
    ssh -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP} $Command
} else {
    # Session interactive
    ssh -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}
}


