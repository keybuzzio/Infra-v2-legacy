# plink_execute.ps1 - Exécute des commandes sur install-01 avec plink
# Utilise plink (PuTTY) qui peut gérer le passphrase automatiquement

param(
    [Parameter(Mandatory=$true)]
    [string]$Command
)

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$SSH_KEY = "$PSScriptRoot\..\..\SSH\keybuzz_infra"
$PASSPHRASE_FILE = "$PSScriptRoot\..\..\SSH\passphrase.txt"

# Lire le passphrase
$passphrase = Get-Content $PASSPHRASE_FILE -Raw | ForEach-Object { $_.Trim() }

Write-Host "Execution sur install-01 avec plink..." -ForegroundColor Cyan
Write-Host "Commande: $Command" -ForegroundColor Yellow
Write-Host ""

# Plink avec passphrase
# Note: plink utilise -pw pour le mot de passe, mais pour une clé avec passphrase,
# il faut d'abord charger la clé dans Pageant ou convertir en .ppk
# Pour l'instant, on utilise plink qui demandera le passphrase une fois
$plinkCmd = "plink.exe -ssh -i `"$SSH_KEY`" -batch ${SSH_USER}@${INSTALL_01_IP} `"$Command`""
Invoke-Expression $plinkCmd


