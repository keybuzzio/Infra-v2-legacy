# connect_to_install01.ps1 - Connexion simple et fiable a install-01
# Usage: .\connect_to_install01.ps1 "commande"
#        .\connect_to_install01.ps1  # Session interactive
#
# Ce script vous permet de vous connecter a install-01
# Vous devrez entrer le passphrase de la cle SSH si Pageant n'est pas configure

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

# Verifier la cle SSH
if (-not (Test-Path $SSH_KEY)) {
    Write-Host "Cle SSH introuvable : $SSH_KEY" -ForegroundColor Red
    exit 1
}

Write-Host "Connexion a install-01..." -ForegroundColor Cyan
Write-Host "   IP: $INSTALL_01_IP" -ForegroundColor Gray
Write-Host "   User: $SSH_USER" -ForegroundColor Gray
Write-Host ""

# Construire la commande SSH
$sshCmd = "ssh -i `"$SSH_KEY`" -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"

if ($Command) {
    Write-Host "Vous devrez entrer:" -ForegroundColor Yellow
    Write-Host "  1. Le passphrase de la cle SSH (si Pageant n'est pas configure)" -ForegroundColor Yellow
    Write-Host "  2. Le mot de passe root du serveur (si necessaire)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Execution de la commande: $Command" -ForegroundColor Gray
    Invoke-Expression "$sshCmd `"$Command`""
} else {
    Write-Host "Vous devrez entrer:" -ForegroundColor Yellow
    Write-Host "  1. Le passphrase de la cle SSH (si Pageant n'est pas configure)" -ForegroundColor Yellow
    Write-Host "  2. Le mot de passe root du serveur (si necessaire)" -ForegroundColor Yellow
    Write-Host ""
    Invoke-Expression $sshCmd
}
