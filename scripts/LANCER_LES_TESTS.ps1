# LANCER_LES_TESTS.ps1 - Script pour lancer les tests sur install-01
# 
# INSTRUCTIONS:
# 1. Exécutez ce script: .\LANCER_LES_TESTS.ps1
# 2. Quand il vous demande "Enter passphrase for key...", tapez votre passphrase
# 3. Appuyez sur Entrée
# 4. Les tests vont démarrer automatiquement

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$SSH_KEY = "$PSScriptRoot\..\..\SSH\keybuzz_infra"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Tests Complets Infrastructure KeyBuzz" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ce script va se connecter a install-01 et executer les tests" -ForegroundColor Yellow
Write-Host ""
Write-Host "ETAPE IMPORTANTE:" -ForegroundColor Yellow
Write-Host "   Dans quelques secondes, vous verrez:" -ForegroundColor Yellow
Write-Host "   'Enter passphrase for key...'" -ForegroundColor Cyan
Write-Host ""
Write-Host "   ALORS:" -ForegroundColor Green
Write-Host "   1. TAPEZ votre passphrase (les caracteres ne s'afficheront pas)" -ForegroundColor Green
Write-Host "   2. APPUYEZ sur Entree" -ForegroundColor Green
Write-Host ""
Write-Host "   La connexion va s'etablir et les tests vont demarrer" -ForegroundColor Yellow
Write-Host ""
Write-Host "Appuyez sur Entree pour continuer..." -ForegroundColor Yellow
$null = Read-Host

Write-Host ""
Write-Host "Connexion a install-01..." -ForegroundColor Cyan
Write-Host ""

# Commande SSH
$sshCmd = "ssh -i `"$SSH_KEY`" -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"

# Script a executer sur install-01
$remoteCommand = @'
echo "=============================================================="
echo "  Tests Complets Infrastructure KeyBuzz"
echo "=============================================================="
echo ""
echo "Date: $(date)"
echo "Host: $(hostname)"
echo "User: $(whoami)"
echo ""

# Aller dans le repertoire des scripts
cd /opt/keybuzz-installer/scripts 2>/dev/null || {
    echo "ERREUR: Repertoire /opt/keybuzz-installer/scripts introuvable"
    echo "   Verifiez que vous etes bien sur install-01"
    exit 1
}

echo "Repertoire: $(pwd)"
echo ""

# Verifier que le script de test existe
if [ ! -f '00_test_complet_infrastructure_haproxy01.sh' ]; then
    echo "ATTENTION: Script 00_test_complet_infrastructure_haproxy01.sh non trouve"
    echo ""
    echo "Scripts de test disponibles:"
    ls -la 00_test*.sh 2>/dev/null | head -10
    echo ""
    echo "Recherche dans tout le repertoire..."
    find . -name '*test*.sh' -type f 2>/dev/null | head -10
    echo ""
    echo "Mise a jour depuis Git..."
    
    # Essayer de mettre a jour depuis Git
    if [ -d '/opt/keybuzz-installer/.git' ]; then
        cd /opt/keybuzz-installer
        git pull origin main 2>/dev/null || git pull 2>/dev/null || true
        cd scripts
    fi
    
    # Si toujours pas trouve
    if [ ! -f '00_test_complet_infrastructure_haproxy01.sh' ]; then
        echo "ERREUR: Script non trouve apres mise a jour Git"
        echo ""
        echo "Le script doit etre transfere ou cree sur install-01"
        exit 1
    fi
fi

echo "OK: Script trouve"
echo ""

# Rendre le script executable
chmod +x 00_test_complet_infrastructure_haproxy01.sh

echo "Demarrage des tests..."
echo ""
echo "=============================================================="
echo ""

# Executer le script de test
./00_test_complet_infrastructure_haproxy01.sh

echo ""
echo "=============================================================="
echo "  Tests termines"
echo "=============================================================="
'@

# Executer la commande
Write-Host "Lancement de la connexion..." -ForegroundColor Cyan
Write-Host ">>> VOUS ALLEZ DEVOIR ENTRER LE PASSPHRASE DANS QUELQUES SECONDES <<<" -ForegroundColor Yellow
Write-Host ""
Start-Sleep -Seconds 2

Invoke-Expression "$sshCmd `"$remoteCommand`""

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Execution terminee" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan

