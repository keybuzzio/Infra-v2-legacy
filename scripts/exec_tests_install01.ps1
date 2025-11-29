# exec_tests_install01.ps1 - Execute les tests sur install-01 via SSH
# Usage: .\exec_tests_install01.ps1
# Pre-requis: Avoir configure ssh-agent avec la clé (voir GUIDE_CONFIGURATION_SSH.md)

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$SSH_KEY = "$PSScriptRoot\..\..\SSH\keybuzz_infra"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Execution des tests sur install-01" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Commande SSH
$sshCmd = "ssh -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"

# Script a executer sur install-01
$remoteCommand = @'
echo '=============================================================='
echo '  Tests Complets Infrastructure KeyBuzz'
echo '=============================================================='
echo ''
echo "Date: $(date)"
echo "Host: $(hostname)"
echo "User: $(whoami)"
echo ''

# Aller dans le repertoire des scripts
cd /opt/keybuzz-installer/scripts 2>/dev/null || {
    echo 'ERREUR: Repertoire /opt/keybuzz-installer/scripts introuvable'
    echo '   Verifiez que vous etes bien sur install-01'
    exit 1
}

echo "Repertoire: $(pwd)"
echo ''

# Verifier que le script de test existe
if [ ! -f '00_test_complet_infrastructure_haproxy01.sh' ]; then
    echo 'ATTENTION: Script 00_test_complet_infrastructure_haproxy01.sh non trouve'
    echo '   Scripts de test disponibles:'
    ls -la 00_test*.sh 2>/dev/null | head -5
    echo ''
    echo '   Mise a jour depuis Git...'
    
    # Le script devrait etre dans le depot git sur install-01
    if [ -d '/opt/keybuzz-installer/.git' ]; then
        cd /opt/keybuzz-installer
        git pull origin main 2>/dev/null || git pull 2>/dev/null || true
        cd scripts
    fi
    
    # Si toujours pas trouve, informer
    if [ ! -f '00_test_complet_infrastructure_haproxy01.sh' ]; then
        echo 'ERREUR: Script non trouve apres mise a jour Git'
        echo '   Le script doit etre transfere manuellement ou etre present dans le depot'
        exit 1
    fi
fi

echo 'OK: Script trouve'
echo ''

# Rendre le script executable
chmod +x 00_test_complet_infrastructure_haproxy01.sh

echo 'Demarrage des tests...'
echo ''

# Executer le script de test
./00_test_complet_infrastructure_haproxy01.sh

echo ''
echo '=============================================================='
echo '  Tests termines'
echo '=============================================================='
'@

Write-Host "Connexion a install-01 et execution des tests..." -ForegroundColor Cyan
Write-Host ""

# Executer la commande
Invoke-Expression "$sshCmd `"$remoteCommand`""

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Execution terminee" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
