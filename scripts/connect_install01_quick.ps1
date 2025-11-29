# connect_install01_quick.ps1 - Connexion rapide à install-01
# Usage: .\connect_install01_quick.ps1 "commande"
#        .\connect_install01_quick.ps1  # Session interactive
#
# PREREQUIS: Exécuter setup_ssh_once.ps1 une première fois
# Ce script se connecte directement sans demander le passphrase

param(
    [Parameter(Mandatory=$false)]
    [string]$Command = ""
)

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"

# Vérifier si ssh-agent a des clés chargées
$keys = ssh-add -l 2>&1
if ($LASTEXITCODE -ne 0 -or $keys -match "The agent has no identities") {
    Write-Host "⚠️  Aucune clé SSH chargée dans ssh-agent" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Exécutez d'abord :" -ForegroundColor Cyan
    Write-Host "  .\setup_ssh_once.ps1" -ForegroundColor White
    Write-Host ""
    exit 1
}

# Se connecter
if ($Command) {
    ssh -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP} $Command
} else {
    ssh -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}
}


