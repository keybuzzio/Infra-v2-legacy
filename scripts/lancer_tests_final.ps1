# lancer_tests_final.ps1 - Lance les tests en utilisant Pageant (recommandé avec PuTTY)
# Pageant doit être démarré avec la clé chargée

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$SSH_KEY = "$PSScriptRoot\..\..\SSH\keybuzz_infra"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Tests Infrastructure KeyBuzz" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Vérifier si Pageant est actif
$pageantProcess = Get-Process pageant -ErrorAction SilentlyContinue
if ($pageantProcess) {
    Write-Host "Pageant est actif (PID: $($pageantProcess.Id))" -ForegroundColor Green
    Write-Host "   Si votre cle est chargee dans Pageant, le passphrase ne sera pas demande" -ForegroundColor Yellow
    Write-Host ""
} else {
    Write-Host "ATTENTION: Pageant n'est pas demarre" -ForegroundColor Yellow
    Write-Host "   Vous devrez entrer le passphrase a chaque connexion" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   Pour utiliser Pageant:" -ForegroundColor Yellow
    Write-Host "   1. Demarrez Pageant depuis le menu Demarrer" -ForegroundColor White
    Write-Host "   2. Cliquez sur l'icone Pageant dans la barre des taches" -ForegroundColor White
    Write-Host "   3. Cliquez sur 'Add Key' et selectionnez votre cle" -ForegroundColor White
    Write-Host "   4. Entrez le passphrase UNE FOIS" -ForegroundColor White
    Write-Host ""
}

# Vérifier si plink est disponible
$plinkPath = Get-Command plink -ErrorAction SilentlyContinue
$sshPath = Get-Command ssh -ErrorAction SilentlyContinue

if ($plinkPath) {
    Write-Host "Utilisation de plink (PuTTY)..." -ForegroundColor Green
    $usePlink = $true
} elseif ($sshPath) {
    Write-Host "Utilisation de ssh standard..." -ForegroundColor Yellow
    $usePlink = $false
} else {
    Write-Host "ERREUR: Ni plink ni ssh trouves" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Script à exécuter sur install-01
$remoteCommand = @'
cd /opt/keybuzz-installer/scripts 2>/dev/null || {
    echo "ERREUR: Repertoire /opt/keybuzz-installer/scripts introuvable"
    exit 1
}

echo "Repertoire: $(pwd)"
echo ""

# Vérifier que le script de test existe
if [ ! -f '00_test_complet_infrastructure_haproxy01.sh' ]; then
    echo "ATTENTION: Script 00_test_complet_infrastructure_haproxy01.sh non trouve"
    echo ""
    echo "Scripts de test disponibles:"
    ls -la 00_test*.sh 2>/dev/null | head -10
    echo ""
    echo "Mise a jour depuis Git..."
    if [ -d '/opt/keybuzz-installer/.git' ]; then
        cd /opt/keybuzz-installer
        git pull origin main 2>/dev/null || git pull 2>/dev/null || true
        cd scripts
    fi
    
    if [ ! -f '00_test_complet_infrastructure_haproxy01.sh' ]; then
        echo "ERREUR: Script non trouve apres mise a jour Git"
        exit 1
    fi
fi

echo "OK: Script trouve"
echo ""

# Rendre le script exécutable
chmod +x 00_test_complet_infrastructure_haproxy01.sh

echo "Demarrage des tests..."
echo ""
echo "=============================================================="
echo ""

# Exécuter le script de test
./00_test_complet_infrastructure_haproxy01.sh

echo ""
echo "=============================================================="
echo "  Tests termines"
echo "=============================================================="
'@

Write-Host "Connexion a install-01..." -ForegroundColor Cyan
Write-Host ""

if ($usePlink) {
    # Utiliser plink (PuTTY) qui peut utiliser Pageant automatiquement
    & plink.exe -ssh "${SSH_USER}@${INSTALL_01_IP}" -batch $remoteCommand
} else {
    # Utiliser ssh standard avec la clé
    & ssh.exe -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${INSTALL_01_IP}" $remoteCommand
}

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Execution terminee" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan

