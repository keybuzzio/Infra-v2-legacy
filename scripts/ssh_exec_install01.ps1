# ssh_exec_install01.ps1 - Exécution simple sur install-01
# Usage: .\ssh_exec_install01.ps1 "commande"
#        .\ssh_exec_install01.ps1  # Session interactive
#
# Ce script vous permettra d'entrer le passphrase manuellement
# Si Pageant est configuré, le passphrase ne sera pas demandé

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

# Construire la commande SSH
$sshCmd = "ssh -i `"$SSH_KEY`" -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"

# Exécuter la commande
if ($Command) {
    Write-Host "🔌 Exécution sur install-01..." -ForegroundColor Cyan
    Write-Host "   Commande: $Command" -ForegroundColor Gray
    Write-Host ""
    Write-Host "⚠️  Si Pageant n'est pas configuré, vous devrez entrer:" -ForegroundColor Yellow
    Write-Host "   1. Le passphrase de la clé SSH" -ForegroundColor Yellow
    Write-Host "   2. Le mot de passe root du serveur" -ForegroundColor Yellow
    Write-Host ""
    Invoke-Expression "$sshCmd `"$Command`""
} else {
    Write-Host "🔌 Connexion interactive à install-01..." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "⚠️  Si Pageant n'est pas configuré, vous devrez entrer:" -ForegroundColor Yellow
    Write-Host "   1. Le passphrase de la clé SSH" -ForegroundColor Yellow
    Write-Host "   2. Le mot de passe root du serveur" -ForegroundColor Yellow
    Write-Host ""
    Invoke-Expression $sshCmd
}
