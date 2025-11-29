# lancer_tests_simple.ps1 - Lance les tests sur install-01
# Ce script se connecte et execute les tests directement
# Vous devrez entrer le passphrase UNE FOIS lors de la connexion

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$SSH_KEY = "$PSScriptRoot\..\..\SSH\keybuzz_infra"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Execution des tests sur install-01" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ce script va:" -ForegroundColor Yellow
Write-Host "  1. Se connecter a install-01" -ForegroundColor Yellow
Write-Host "  2. Verifier que le script de test existe" -ForegroundColor Yellow
Write-Host "  3. Executer les tests complets" -ForegroundColor Yellow
Write-Host ""
Write-Host "Note: Vous devrez entrer le passphrase UNE FOIS" -ForegroundColor Yellow
Write-Host ""

# Verifier la cle SSH
if (-not (Test-Path $SSH_KEY)) {
    Write-Host "ERREUR: Cle SSH introuvable: $SSH_KEY" -ForegroundColor Red
    exit 1
}

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
        echo "Options:"
        echo "  1. Le script doit etre transfere manuellement"
        echo "  2. Ou etre present dans le depot Git"
        echo ""
        echo "Pour transferer le script depuis votre machine Windows:"
        echo "  scp -i chemin/vers/cle chemin/vers/00_test_complet_infrastructure_haproxy01.sh root@91.98.128.153:/opt/keybuzz-installer/scripts/"
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

Write-Host "Connexion a install-01..." -ForegroundColor Cyan
Write-Host "   Entrez le passphrase de la cle SSH quand demande" -ForegroundColor Yellow
Write-Host ""

# Executer la commande
Invoke-Expression "$sshCmd `"$remoteCommand`""

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Execution terminee" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan

