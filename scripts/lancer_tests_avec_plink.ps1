# lancer_tests_avec_plink.ps1 - Lance les tests via plink (PuTTY)
# Utilise plink qui ouvre une fenetre pour le passphrase

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$SSH_KEY = "$PSScriptRoot\..\..\SSH\keybuzz_infra"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Tests Infrastructure KeyBuzz via PuTTY/plink" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Verifier si plink est disponible
$plinkPath = Get-Command plink -ErrorAction SilentlyContinue
if (-not $plinkPath) {
    Write-Host "ERREUR: plink (PuTTY) non trouve" -ForegroundColor Red
    Write-Host "   Installez PuTTY depuis: https://www.putty.org/" -ForegroundColor Yellow
    Write-Host "   Ou ajoutez PuTTY au PATH" -ForegroundColor Yellow
    exit 1
}

Write-Host "plink trouve: $($plinkPath.Source)" -ForegroundColor Green
Write-Host ""

# Verifier la cle SSH
if (-not (Test-Path $SSH_KEY)) {
    Write-Host "ERREUR: Cle SSH introuvable: $SSH_KEY" -ForegroundColor Red
    exit 1
}

Write-Host "Cle SSH: $SSH_KEY" -ForegroundColor Green
Write-Host ""
Write-Host "IMPORTANT:" -ForegroundColor Yellow
Write-Host "  Une fenetre PuTTY va s'ouvrir pour demander le passphrase" -ForegroundColor Yellow
Write-Host "  Tapez votre passphrase dans cette fenetre" -ForegroundColor Yellow
Write-Host ""
Write-Host "Appuyez sur Entree pour continuer..." -ForegroundColor Cyan
$null = Read-Host

# Commande plink
# -ssh : mode SSH
# -i : fichier cle
# -batch : mode non-interactif (mais passphrase sera demande)
# Ou sans -batch pour avoir la fenetre interactive

$remoteCommand = @'
cd /opt/keybuzz-installer/scripts 2>/dev/null || {
    echo "ERREUR: Repertoire /opt/keybuzz-installer/scripts introuvable"
    exit 1
}

if [ ! -f '00_test_complet_infrastructure_haproxy01.sh' ]; then
    echo "ATTENTION: Script 00_test_complet_infrastructure_haproxy01.sh non trouve"
    echo ""
    echo "Scripts disponibles:"
    ls -la 00_test*.sh 2>/dev/null | head -10
    echo ""
    echo "Mise a jour depuis Git..."
    if [ -d '/opt/keybuzz-installer/.git' ]; then
        cd /opt/keybuzz-installer
        git pull origin main 2>/dev/null || git pull 2>/dev/null || true
        cd scripts
    fi
    
    if [ ! -f '00_test_complet_infrastructure_haproxy01.sh' ]; then
        echo "ERREUR: Script non trouve"
        exit 1
    fi
fi

chmod +x 00_test_complet_infrastructure_haproxy01.sh
./00_test_complet_infrastructure_haproxy01.sh
'@

Write-Host "Connexion a install-01 via plink..." -ForegroundColor Cyan
Write-Host "   Une fenetre PuTTY va s'ouvrir pour le passphrase" -ForegroundColor Yellow
Write-Host ""

# Utiliser plink sans -batch pour avoir la fenetre interactive du passphrase
& plink.exe -ssh -i "$SSH_KEY" "${SSH_USER}@${INSTALL_01_IP}" $remoteCommand

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Execution terminee" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan

