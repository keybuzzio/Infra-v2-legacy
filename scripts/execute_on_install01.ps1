# execute_on_install01.ps1 - Exécute des commandes sur install-01
# Ce script transfère et exécute des commandes via SSH

param(
    [Parameter(Mandatory=$true)]
    [string]$Command
)

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$SSH_KEY = "$PSScriptRoot\..\..\SSH\keybuzz_infra"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " Execution sur install-01" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Commande : $Command" -ForegroundColor Yellow
Write-Host ""
Write-Host "NOTE: Vous devrez entrer le passphrase une fois" -ForegroundColor Yellow
Write-Host ""

# Exécuter la commande
$sshCmd = "ssh -i `"$SSH_KEY`" -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP} `"$Command`""
Invoke-Expression $sshCmd

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " Execution terminee" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan


