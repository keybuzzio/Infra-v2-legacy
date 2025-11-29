# ssh_connect_install01.ps1 - Connexion automatique à install-01 avec passphrase
# Usage: .\ssh_connect_install01.ps1 "commande"
#        .\ssh_connect_install01.ps1  # Session interactive

param(
    [Parameter(Mandatory=$false)]
    [string]$Command = ""
)

$ErrorActionPreference = "Stop"

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$SSH_KEY = "$PSScriptRoot\..\..\SSH\keybuzz_infra"
$PASSPHRASE_FILE = "$PSScriptRoot\..\..\SSH\passphrase.txt"

# Vérifier les fichiers
if (-not (Test-Path $SSH_KEY)) {
    Write-Host "❌ Clé SSH introuvable : $SSH_KEY" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $PASSPHRASE_FILE)) {
    Write-Host "❌ Fichier passphrase introuvable : $PASSPHRASE_FILE" -ForegroundColor Red
    exit 1
}

# Lire le passphrase
$passphrase = Get-Content $PASSPHRASE_FILE -Raw | ForEach-Object { $_.TrimEnd() }

# Fonction pour démarrer ssh-agent et charger la clé
function Start-SSHAgent {
    # Vérifier si ssh-agent est déjà démarré
    $agentProcess = Get-Process ssh-agent -ErrorAction SilentlyContinue
    
    if (-not $agentProcess) {
        Write-Host "🔧 Démarrage de ssh-agent..." -ForegroundColor Cyan
        # Démarrer ssh-agent en arrière-plan
        $null = Start-Process ssh-agent -NoNewWindow -PassThru
        Start-Sleep -Seconds 2
    }
    
    # Vérifier si la clé est déjà chargée
    $keysLoaded = ssh-add -l 2>&1
    if ($LASTEXITCODE -eq 0) {
        # Vérifier si notre clé est déjà chargée
        $keyFingerprint = ssh-keygen -lf $SSH_KEY 2>&1 | Select-String -Pattern "^\d+\s+([\w:]+)"
        if ($keyFingerprint) {
            $fp = $keyFingerprint.Matches[0].Groups[1].Value
            if ($keysLoaded -match $fp) {
                Write-Host "✅ Clé SSH déjà chargée dans ssh-agent" -ForegroundColor Green
                return $true
            }
        }
    }
    
    # Charger la clé avec le passphrase
    Write-Host "🔑 Chargement de la clé SSH dans ssh-agent..." -ForegroundColor Cyan
    $passphrase | ssh-add $SSH_KEY 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Clé SSH chargée avec succès" -ForegroundColor Green
        return $true
    } else {
        Write-Host "⚠️  Impossible de charger automatiquement la clé. Tentative manuelle..." -ForegroundColor Yellow
        return $false
    }
}

# Essayer d'utiliser ssh-agent
$useAgent = $false
try {
    $useAgent = Start-SSHAgent
} catch {
    Write-Host "⚠️  ssh-agent non disponible, utilisation directe de SSH" -ForegroundColor Yellow
}

# Construire la commande SSH
if ($useAgent) {
    # Si la clé est dans ssh-agent, on peut utiliser SSH sans spécifier -i
    $sshCmd = "ssh -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"
} else {
    # Sinon, utiliser la clé directement (demandera le passphrase manuellement)
    $sshCmd = "ssh -i `"$SSH_KEY`" -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"
}

# Exécuter la commande
if ($Command) {
    Write-Host "🔌 Connexion à install-01 et exécution de la commande..." -ForegroundColor Cyan
    Write-Host "   Commande: $Command" -ForegroundColor Gray
    if ($useAgent) {
        Invoke-Expression "$sshCmd `"$Command`""
    } else {
        Write-Host "⚠️  Vous devrez entrer le passphrase manuellement" -ForegroundColor Yellow
        $passphrase | Invoke-Expression "$sshCmd `"$Command`""
    }
} else {
    Write-Host "🔌 Connexion interactive à install-01..." -ForegroundColor Cyan
    if ($useAgent) {
        Invoke-Expression $sshCmd
    } else {
        Write-Host "⚠️  Vous devrez entrer le passphrase manuellement" -ForegroundColor Yellow
        Invoke-Expression $sshCmd
    }
}

