# auto_ssh_install01.ps1 - Connexion automatique à install-01 avec passphrase
# Usage: .\auto_ssh_install01.ps1 "commande"
#        .\auto_ssh_install01.ps1  # Session interactive

param(
    [Parameter(Mandatory=$false)]
    [string]$Command = ""
)

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$PASSPHRASE_FILE = "$PSScriptRoot\..\..\SSH\passphrase.txt"
$SSH_KEY = "$PSScriptRoot\..\..\SSH\keybuzz_infra"

# Vérifier les fichiers
if (-not (Test-Path $PASSPHRASE_FILE)) {
    Write-Host "❌ Fichier passphrase introuvable : $PASSPHRASE_FILE" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $SSH_KEY)) {
    Write-Host "❌ Clé SSH introuvable : $SSH_KEY" -ForegroundColor Red
    exit 1
}

# Lire le passphrase
$passphrase = Get-Content $PASSPHRASE_FILE -Raw | ForEach-Object { $_.Trim() }

# Utiliser WSL ou Git Bash pour sshpass
$useWSL = Get-Command wsl -ErrorAction SilentlyContinue
$useBash = Get-Command bash -ErrorAction SilentlyContinue

if ($useWSL) {
    # Convertir les chemins Windows en chemins WSL
    $wslKey = wsl wslpath -a $SSH_KEY
    $sshCmd = "wsl sshpass -p '$passphrase' ssh -i '$wslKey' -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"
} elseif ($useBash) {
    # Utiliser Git Bash
    $bashKey = $SSH_KEY -replace '\\', '/' -replace '^C:', '/c' -replace '^([A-Z]):', '/$1'
    $bashKey = $bashKey.ToLower()
    $sshCmd = "bash -c 'sshpass -p `"$passphrase`" ssh -i `"$bashKey`" -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"
} else {
    Write-Host "⚠️  WSL ou Git Bash requis pour sshpass" -ForegroundColor Yellow
    Write-Host "   Connexion manuelle (vous devrez entrer le passphrase) :" -ForegroundColor Yellow
    $sshCmd = "ssh -i `"$SSH_KEY`" -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"
}

if ($Command) {
    Write-Host "🔌 Exécution sur install-01 : $Command" -ForegroundColor Cyan
    if ($useBash) {
        $sshCmd += " `"$Command`"'"
    } else {
        $sshCmd += " `"$Command`""
    }
    Invoke-Expression $sshCmd
} else {
    Write-Host "🔌 Connexion interactive à install-01..." -ForegroundColor Cyan
    if ($useBash) {
        $sshCmd += "'"
    }
    Invoke-Expression $sshCmd
}


