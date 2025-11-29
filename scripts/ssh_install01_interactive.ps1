# ssh_install01_interactive.ps1 - Connexion interactive à install-01
# Ce script ouvre une fenêtre PowerShell interactive pour entrer le passphrase
# Usage: .\ssh_install01_interactive.ps1 "commande"
#        .\ssh_install01_interactive.ps1  # Session interactive

param(
    [Parameter(Mandatory=$false)]
    [string]$Command = ""
)

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"

# Chemins
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$SSH_KEY = Join-Path $ProjectRoot "SSH\keybuzz_infra"

# Vérifier la clé SSH
if (-not (Test-Path $SSH_KEY)) {
    Write-Host "❌ Clé SSH introuvable : $SSH_KEY" -ForegroundColor Red
    exit 1
}

Write-Host "🔌 Connexion à install-01..." -ForegroundColor Cyan
Write-Host "   IP: $INSTALL_01_IP" -ForegroundColor Gray
Write-Host "   User: $SSH_USER" -ForegroundColor Gray
Write-Host ""
Write-Host "⚠️  Une fenêtre PowerShell va s'ouvrir pour la connexion SSH" -ForegroundColor Yellow
Write-Host "   Vous devrez entrer le passphrase dans cette fenêtre" -ForegroundColor Yellow
Write-Host ""

# Construire la commande SSH
$sshCmd = "ssh -i `"$SSH_KEY`" -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"

if ($Command) {
    $sshCmd += " `"$Command`""
    Write-Host "   Commande à exécuter: $Command" -ForegroundColor Gray
}

# Lancer SSH dans une nouvelle fenêtre PowerShell interactive
Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "cd '$PSScriptRoot'; $sshCmd"

