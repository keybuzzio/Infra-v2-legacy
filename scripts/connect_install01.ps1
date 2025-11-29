# connect_install01.ps1 - Connexion simple et fiable à install-01
# Usage: .\connect_install01.ps1 "commande"
#        .\connect_install01.ps1  # Session interactive
#
# Solution simple: utilise ssh-agent avec AskPass helper pour automatiser le passphrase

param(
    [Parameter(Mandatory=$false)]
    [string]$Command = ""
)

$ErrorActionPreference = "Continue"

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"

# Chemins
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$SSH_KEY = Join-Path $ProjectRoot "SSH\keybuzz_infra"
$PASSPHRASE_FILE = Join-Path $ProjectRoot "SSH\passphrase.txt"
$ASKPASS_HELPER = Join-Path $ScriptDir "ssh_askpass_helper.ps1"

# Vérifier les fichiers
if (-not (Test-Path $SSH_KEY)) {
    Write-Host "❌ Clé SSH introuvable : $SSH_KEY" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $PASSPHRASE_FILE)) {
    Write-Host "❌ Fichier passphrase introuvable : $PASSPHRASE_FILE" -ForegroundColor Red
    exit 1
}

# Démarrer et configurer ssh-agent
$agentService = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($agentService -and $agentService.Status -ne 'Running') {
    Write-Host "🔧 Démarrage du service ssh-agent..." -ForegroundColor Cyan
    Start-Service ssh-agent
    Start-Sleep -Seconds 2
}

# Vérifier si la clé est déjà chargée
$loadedKeys = ssh-add -l 2>&1
$keyAlreadyLoaded = $false

if ($LASTEXITCODE -eq 0) {
    # Vérifier si des clés sont déjà chargées
    if ($loadedKeys -match "keybuzz_infra" -or $loadedKeys.Count -gt 0) {
        Write-Host "✅ Clés SSH déjà chargées dans ssh-agent" -ForegroundColor Green
        $keyAlreadyLoaded = $true
    }
}

# Charger la clé si nécessaire
if (-not $keyAlreadyLoaded) {
    Write-Host "🔑 Chargement de la clé SSH dans ssh-agent..." -ForegroundColor Cyan
    
    # Utiliser le helper AskPass
    $env:SSH_ASKPASS = "powershell.exe"
    $env:SSH_ASKPASS_REQUIRE = "force"
    $env:DISPLAY = "1"
    
    # Passer les arguments au helper
    $askpassArgs = "-ExecutionPolicy Bypass -File `"$ASKPASS_HELPER`" -PassphraseFile `"$PASSPHRASE_FILE`""
    $env:SSH_ASKPASS = "powershell.exe -ExecutionPolicy Bypass -File `"$ASKPASS_HELPER`" -PassphraseFile `"$PASSPHRASE_FILE`""
    
    # Essayer de charger la clé
    # Note: ssh-add avec SSH_ASKPASS peut ne pas fonctionner parfaitement sur Windows
    # On va donc essayer mais avoir un fallback
    $addResult = ssh-add $SSH_KEY 2>&1
    
    if ($LASTEXITCODE -eq 0 -or $addResult -match "Identity added|already loaded") {
        Write-Host "✅ Clé SSH chargée avec succès" -ForegroundColor Green
        $keyAlreadyLoaded = $true
    } else {
        Write-Host "⚠️  Impossible de charger automatiquement la clé dans ssh-agent" -ForegroundColor Yellow
        Write-Host "   Utilisation directe de SSH (vous devrez entrer le passphrase)" -ForegroundColor Yellow
    }
    
    # Nettoyer les variables d'environnement
    Remove-Item Env:\SSH_ASKPASS -ErrorAction SilentlyContinue
    Remove-Item Env:\SSH_ASKPASS_REQUIRE -ErrorAction SilentlyContinue
    Remove-Item Env:\DISPLAY -ErrorAction SilentlyContinue
}

# Construire la commande SSH
if ($keyAlreadyLoaded) {
    # Si la clé est dans ssh-agent, utiliser SSH normal
    $sshCmd = "ssh -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"
} else {
    # Sinon, utiliser la clé directement
    $sshCmd = "ssh -i `"$SSH_KEY`" -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"
}

# Exécuter la commande
if ($Command) {
    Write-Host "🔌 Exécution sur install-01..." -ForegroundColor Cyan
    Write-Host "   Commande: $Command" -ForegroundColor Gray
    Invoke-Expression "$sshCmd `"$Command`""
} else {
    Write-Host "🔌 Connexion interactive à install-01..." -ForegroundColor Cyan
    if (-not $keyAlreadyLoaded) {
        Write-Host "⚠️  Entrez le passphrase lorsqu'il vous sera demandé :" -ForegroundColor Yellow
    }
    Invoke-Expression $sshCmd
}

