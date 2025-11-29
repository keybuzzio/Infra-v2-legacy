# ssh_install01.ps1 - Script PRINCIPAL pour connexion a install-01
# Usage: .\ssh_install01.ps1 "commande"
#        .\ssh_install01.ps1  # Session interactive
#
# Ce script utilise Pageant + plink pour une connexion fiable et automatique
# REQUIS: Pageant doit etre actif avec la cle SSH chargee

param(
    [Parameter(Mandatory=$false)]
    [string]$Command = ""
)

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"

# Verifier si plink est disponible
$plinkCommand = Get-Command plink -ErrorAction SilentlyContinue
if (-not $plinkCommand) {
    Write-Host "ERREUR: Plink n'est pas disponible. Installation de PuTTY requise." -ForegroundColor Red
    exit 1
}

# Verifier si Pageant est actif
$pageantProcess = Get-Process pageant -ErrorAction SilentlyContinue
if (-not $pageantProcess) {
    Write-Host "ERREUR: Pageant n'est pas actif." -ForegroundColor Red
    Write-Host ""
    Write-Host "Veuillez demarrer Pageant et charger votre cle SSH:" -ForegroundColor Yellow
    Write-Host "  1. Ouvrir Pageant depuis le menu Demarrer" -ForegroundColor Gray
    Write-Host "  2. Clic droit sur l'icone Pageant dans la barre des taches" -ForegroundColor Gray
    Write-Host "  3. Selectionner 'Add Key' et charger votre cle SSH" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

# Utiliser plink (qui utilisera automatiquement Pageant si une cle correspondante est chargee)
if ($Command) {
    plink -ssh -batch -no-antispoof ${SSH_USER}@${INSTALL_01_IP} $Command
} else {
    plink -ssh ${SSH_USER}@${INSTALL_01_IP}
}
