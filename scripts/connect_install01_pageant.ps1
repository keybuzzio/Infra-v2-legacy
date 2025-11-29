# connect_install01_pageant.ps1 - Connexion a install-01 via Pageant
# Usage: .\connect_install01_pageant.ps1 "commande"
#        .\connect_install01_pageant.ps1  # Session interactive
#
# Ce script utilise Pageant pour automatiser la connexion SSH

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
$SSH_KEY_PPK = Join-Path $ProjectRoot "SSH\keybuzz_infra.ppk"

# Verifier si plink est disponible
$plinkCommand = Get-Command plink -ErrorAction SilentlyContinue
if (-not $plinkCommand) {
    Write-Host "Plink n'est pas disponible. Installation de PuTTY requise." -ForegroundColor Red
    exit 1
}

# Verifier si Pageant est actif
$pageantProcess = Get-Process pageant -ErrorAction SilentlyContinue
if (-not $pageantProcess) {
    Write-Host "Pageant n'est pas actif." -ForegroundColor Red
    Write-Host "Veuillez demarrer Pageant et charger votre cle SSH." -ForegroundColor Yellow
    exit 1
}

Write-Host "Pageant est actif. Utilisation de plink..." -ForegroundColor Green
Write-Host "Connexion a install-01..." -ForegroundColor Cyan
Write-Host "   IP: $INSTALL_01_IP" -ForegroundColor Gray
Write-Host "   User: $SSH_USER" -ForegroundColor Gray
Write-Host ""

# Utiliser plink (qui utilisera automatiquement Pageant si une cle correspondante est chargee)
# Plink cherchera automatiquement dans Pageant une cle qui correspond au serveur
if ($Command) {
    Write-Host "Execution de la commande: $Command" -ForegroundColor Gray
    plink -ssh -batch -no-antispoof ${SSH_USER}@${INSTALL_01_IP} $Command
} else {
    Write-Host "Connexion interactive a install-01..." -ForegroundColor Cyan
    plink -ssh ${SSH_USER}@${INSTALL_01_IP}
}

