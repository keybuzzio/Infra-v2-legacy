# ssh_install01_simple.ps1 - Solution simple et fiable pour se connecter à install-01
# Usage: .\ssh_install01_simple.ps1 "commande"
#        .\ssh_install01_simple.ps1  # Session interactive
#
# Ce script utilise ssh-agent pour gérer automatiquement le passphrase

param(
    [Parameter(Mandatory=$false)]
    [string]$Command = ""
)

$ErrorActionPreference = "Continue"

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"

# Chemins relatifs depuis le script
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$SSH_KEY = Join-Path $ProjectRoot "SSH\keybuzz_infra"
$PASSPHRASE_FILE = Join-Path $ProjectRoot "SSH\passphrase.txt"

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
$passphrase = (Get-Content $PASSPHRASE_FILE -Raw).Trim()

# Fonction pour charger la clé dans ssh-agent
function Add-SSHKeyToAgent {
    param(
        [string]$KeyPath,
        [string]$Passphrase
    )
    
    # Vérifier si ssh-agent est démarré
    $agentService = Get-Service ssh-agent -ErrorAction SilentlyContinue
    if (-not $agentService) {
        Write-Host "❌ ssh-agent service non disponible" -ForegroundColor Red
        return $false
    }
    
    # Démarrer le service ssh-agent s'il n'est pas démarré
    if ($agentService.Status -ne 'Running') {
        Write-Host "🔧 Démarrage du service ssh-agent..." -ForegroundColor Cyan
        Start-Service ssh-agent
        Start-Sleep -Seconds 2
    }
    
    # Vérifier si la clé est déjà chargée
    $loadedKeys = ssh-add -l 2>&1
    if ($LASTEXITCODE -eq 0) {
        $keyFingerprint = ssh-keygen -lf $KeyPath 2>&1 | Select-String -Pattern "^\d+\s+([\w:]+)"
        if ($keyFingerprint -and $loadedKeys -match $keyFingerprint.Matches[0].Groups[1].Value) {
            Write-Host "✅ Clé SSH déjà chargée dans ssh-agent" -ForegroundColor Green
            return $true
        }
    }
    
    # Créer un script temporaire pour ssh-add avec le passphrase
    $tempScript = Join-Path $env:TEMP "ssh_add_$(Get-Random).ps1"
    
    # Créer un helper qui retourne le passphrase
    $helperScript = @"
`$passphrase = '$passphrase'
Write-Output `$passphrase
"@
    
    Set-Content -Path $tempScript -Value $helperScript -Force
    
    # Essayer de charger la clé en utilisant le helper
    Write-Host "🔑 Chargement de la clé SSH dans ssh-agent..." -ForegroundColor Cyan
    
    # Utiliser la variable d'environnement SSH_ASKPASS
    $env:SSH_ASKPASS = $tempScript
    $env:DISPLAY = "1"  # Nécessaire pour ssh-add avec SSH_ASKPASS
    
    # Essayer avec ssh-add
    $result = echo $passphrase | ssh-add $KeyPath 2>&1
    
    # Nettoyer le script temporaire
    Remove-Item -Path $tempScript -Force -ErrorAction SilentlyContinue
    
    if ($LASTEXITCODE -eq 0 -or $result -match "Identity added") {
        Write-Host "✅ Clé SSH chargée avec succès" -ForegroundColor Green
        return $true
    } else {
        Write-Host "⚠️  Impossible de charger automatiquement la clé" -ForegroundColor Yellow
        Write-Host "   Tentative manuelle..." -ForegroundColor Yellow
        return $false
    }
}

# Essayer de charger la clé dans ssh-agent
$keyLoaded = Add-SSHKeyToAgent -KeyPath $SSH_KEY -Passphrase $passphrase

# Construire la commande SSH
if ($keyLoaded) {
    # Si la clé est dans ssh-agent, utiliser SSH normal
    $sshCmd = "ssh -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"
} else {
    # Sinon, utiliser la clé directement (demandera le passphrase)
    $sshCmd = "ssh -i `"$SSH_KEY`" -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"
}

# Exécuter la commande
if ($Command) {
    Write-Host "🔌 Exécution sur install-01..." -ForegroundColor Cyan
    Write-Host "   Commande: $Command" -ForegroundColor Gray
    
    if ($keyLoaded) {
        Invoke-Expression "$sshCmd `"$Command`""
    } else {
        Write-Host ""
        Write-Host "⚠️  Entrez le passphrase lorsqu'il vous sera demandé :" -ForegroundColor Yellow
        Invoke-Expression "$sshCmd `"$Command`""
    }
} else {
    Write-Host "🔌 Connexion interactive à install-01..." -ForegroundColor Cyan
    
    if ($keyLoaded) {
        Invoke-Expression $sshCmd
    } else {
        Write-Host ""
        Write-Host "⚠️  Entrez le passphrase lorsqu'il vous sera demandé :" -ForegroundColor Yellow
        Invoke-Expression $sshCmd
    }
}

