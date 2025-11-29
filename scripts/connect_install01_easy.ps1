# connect_install01_easy.ps1 - Connexion SSH simplifiée à install-01
# Usage: .\connect_install01_easy.ps1 "commande"
#        .\connect_install01_easy.ps1  # Session interactive
#
# Ce script gère automatiquement ssh-agent et la clé SSH
# Vous devrez entrer le passphrase UNE SEULE FOIS par session

param(
    [Parameter(Mandatory=$false)]
    [string]$Command = ""
)

# Configuration
$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$SSH_KEY_PATH = "$PSScriptRoot\..\..\SSH\keybuzz_infra"
$PASSPHRASE = "^k467G2.y%b32[A}2f4Rii(yBnxaqQ44@gHi#iM7X;hmL]rZ-,,SW9z9=n4T5yNG2Mt)4U/{_d7+YN3qPp4?8*:D8B!~8$YzZ32K"

# Fonction pour vérifier si ssh-agent est actif
function Test-SshAgent {
    $agent = Get-Service ssh-agent -ErrorAction SilentlyContinue
    if ($agent -and $agent.Status -eq 'Running') {
        return $true
    }
    return $false
}

# Fonction pour démarrer ssh-agent
function Start-SshAgent {
    $agent = Get-Service ssh-agent -ErrorAction SilentlyContinue
    if ($agent) {
        if ($agent.Status -ne 'Running') {
            Write-Host "🚀 Démarrage du service ssh-agent..." -ForegroundColor Yellow
            Start-Service ssh-agent
            Start-Sleep -Seconds 2
        }
    } else {
        Write-Host "⚠️  Service ssh-agent non disponible" -ForegroundColor Yellow
        Write-Host "   Tentative de démarrage manuel..." -ForegroundColor Yellow
        # Essayer de démarrer ssh-agent manuellement
        $env:SSH_AUTH_SOCK = ""
        $env:SSH_AGENT_PID = ""
    }
}

# Fonction pour vérifier si la clé est chargée
function Test-SshKeyLoaded {
    $keys = ssh-add -l 2>&1
    if ($LASTEXITCODE -eq 0) {
        # Vérifier si notre clé est dans la liste
        $keyFingerprint = ssh-keygen -lf $SSH_KEY_PATH 2>&1 | Select-Object -First 1
        if ($keyFingerprint -match "^\d+") {
            $fingerprint = ($keyFingerprint -split '\s+')[1]
            if ($keys -match $fingerprint) {
                return $true
            }
        }
        # Fallback: vérifier par nom de fichier dans le commentaire
        if ($keys -match "keybuzz") {
            return $true
        }
    }
    return $false
}

# Fonction pour charger la clé dans ssh-agent
function Add-SshKey {
    Write-Host "📝 Chargement de la clé SSH dans ssh-agent..." -ForegroundColor Yellow
    Write-Host "   Vous devrez entrer le passphrase UNE SEULE FOIS" -ForegroundColor Yellow
    Write-Host ""
    
    # Méthode 1: Essayer avec le passphrase via un script temporaire
    # Note: ssh-add sur Windows ne supporte pas directement le passphrase via stdin
    # On va utiliser une méthode avec expect-like functionality via PowerShell
    
    # Créer un script temporaire qui utilise le passphrase
    $tempScript = [System.IO.Path]::GetTempFileName() + ".ps1"
    $tempScriptContent = @"
`$passphrase = '$PASSPHRASE'
`$process = Start-Process -FilePath 'ssh-add' -ArgumentList '$SSH_KEY_PATH' -NoNewWindow -Wait -PassThru -RedirectStandardInput (New-TemporaryFile).FullName
"@
    
    # Méthode alternative: utiliser ssh-add avec interaction manuelle
    # C'est la méthode la plus fiable sur Windows
    Write-Host "   Entrez le passphrase quand demandé..." -ForegroundColor Cyan
    ssh-add $SSH_KEY_PATH
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Clé SSH chargée avec succès" -ForegroundColor Green
        return $true
    } else {
        Write-Host "❌ Échec du chargement de la clé" -ForegroundColor Red
        return $false
    }
}

# Vérifier que la clé existe
if (-not (Test-Path $SSH_KEY_PATH)) {
    Write-Host "❌ Clé SSH introuvable : $SSH_KEY_PATH" -ForegroundColor Red
    exit 1
}

# Vérifier/démarrer ssh-agent
if (-not (Test-SshAgent)) {
    Start-SshAgent
}

# Vérifier si la clé est déjà chargée
if (-not (Test-SshKeyLoaded)) {
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  Configuration de la connexion SSH" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    if (-not (Add-SshKey)) {
        Write-Host ""
        Write-Host "❌ Impossible de charger la clé SSH" -ForegroundColor Red
        Write-Host "   Veuillez réessayer manuellement avec: ssh-add $SSH_KEY_PATH" -ForegroundColor Yellow
        exit 1
    }
    Write-Host ""
} else {
    Write-Host "✅ Clé SSH déjà chargée dans ssh-agent" -ForegroundColor Green
}

# Se connecter au serveur
Write-Host "🔌 Connexion à install-01..." -ForegroundColor Cyan
Write-Host ""

if ($Command) {
    # Exécuter une commande
    ssh -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP} $Command
} else {
    # Session interactive
    ssh -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}
}


