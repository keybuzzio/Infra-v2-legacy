# lancer_tests_pageant.ps1 - Lance les tests en utilisant Pageant (PuTTY Agent)
# AVANTAGE: Le passphrase est demande UNE FOIS dans Pageant, puis plus besoin

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$SSH_KEY = "$PSScriptRoot\..\..\SSH\keybuzz_infra"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Tests Infrastructure KeyBuzz via Pageant" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Verifier si Pageant est en cours d'execution
$pageantProcess = Get-Process pageant -ErrorAction SilentlyContinue

if (-not $pageantProcess) {
    Write-Host "Pageant n'est pas demarre" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "ETAPES:" -ForegroundColor Yellow
    Write-Host "  1. Demarrez Pageant (depuis le menu Demarrer ou depuis PuTTY)" -ForegroundColor White
    Write-Host "  2. Cliquez sur l'icone Pageant dans la barre des taches (system tray)" -ForegroundColor White
    Write-Host "  3. Cliquez sur 'Add Key'" -ForegroundColor White
    Write-Host "  4. Selectionnez votre cle: $SSH_KEY" -ForegroundColor White
    Write-Host "  5. Entrez le passphrase UNE FOIS" -ForegroundColor White
    Write-Host ""
    Write-Host "  OU si vous avez une cle .ppk:" -ForegroundColor Yellow
    Write-Host "    - Utilisez votre fichier .ppk au lieu de la cle OpenSSH" -ForegroundColor White
    Write-Host ""
    
    $response = Read-Host "Pageant est-il maintenant demarre avec votre cle chargee ? (O/N)"
    if ($response -ne "O" -and $response -ne "o" -and $response -ne "Y" -and $response -ne "y") {
        Write-Host "Veuillez demarrer Pageant et charger votre cle, puis relancer ce script" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "Pageant est actif (PID: $($pageantProcess.Id))" -ForegroundColor Green
    Write-Host ""
    Write-Host "Assurez-vous que votre cle SSH est chargee dans Pageant" -ForegroundColor Yellow
    Write-Host ""
}

# Verifier si plink est disponible
$plinkPath = Get-Command plink -ErrorAction SilentlyContinue
if (-not $plinkPath) {
    Write-Host "ERREUR: plink (PuTTY) non trouve" -ForegroundColor Red
    exit 1
}

$remoteCommand = @'
cd /opt/keybuzz-installer/scripts 2>/dev/null || {
    echo "ERREUR: Repertoire introuvable"
    exit 1
}

if [ ! -f '00_test_complet_infrastructure_haproxy01.sh' ]; then
    echo "Script non trouve, mise a jour depuis Git..."
    if [ -d '/opt/keybuzz-installer/.git' ]; then
        cd /opt/keybuzz-installer && git pull 2>/dev/null || true && cd scripts
    fi
fi

if [ -f '00_test_complet_infrastructure_haproxy01.sh' ]; then
    chmod +x 00_test_complet_infrastructure_haproxy01.sh
    ./00_test_complet_infrastructure_haproxy01.sh
else
    echo "ERREUR: Script de test non trouve"
    exit 1
fi
'@

Write-Host "Connexion a install-01..." -ForegroundColor Cyan
Write-Host "   Avec Pageant, pas besoin de passphrase!" -ForegroundColor Green
Write-Host ""

# Utiliser plink qui va utiliser Pageant automatiquement
& plink.exe -ssh "${SSH_USER}@${INSTALL_01_IP}" -batch $remoteCommand

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Execution terminee" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan

