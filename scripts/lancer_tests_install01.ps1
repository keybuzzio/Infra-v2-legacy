# lancer_tests_install01.ps1 - Lance les tests complets sur install-01
# Usage: .\lancer_tests_install01.ps1

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$SSH_KEY = "$PSScriptRoot\..\..\SSH\keybuzz_infra"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Connexion à install-01 et exécution des tests" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Vérifier la clé SSH
if (-not (Test-Path $SSH_KEY)) {
    Write-Host "❌ Clé SSH introuvable : $SSH_KEY" -ForegroundColor Red
    exit 1
}

Write-Host "📋 Étapes :" -ForegroundColor Yellow
Write-Host "  1. Connexion à install-01 (vous devrez entrer le passphrase une fois)" -ForegroundColor Yellow
Write-Host "  2. Vérification que le script de test existe" -ForegroundColor Yellow
Write-Host "  3. Exécution du script de test" -ForegroundColor Yellow
Write-Host ""

# Commande SSH
$sshCmd = "ssh -i `"$SSH_KEY`" -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"

# Script à exécuter sur install-01
$remoteScript = @"
echo '=============================================================='
echo '  Tests Complets Infrastructure KeyBuzz'
echo '=============================================================='
echo ''
echo 'Date: \$(date)'
echo ''

# Aller dans le répertoire des scripts
cd /opt/keybuzz-installer/scripts 2>/dev/null || {
    echo '❌ Répertoire /opt/keybuzz-installer/scripts introuvable'
    echo '   Vérifiez que vous êtes bien sur install-01'
    exit 1
}

# Vérifier que le script de test existe
if [ ! -f '00_test_complet_infrastructure_haproxy01.sh' ]; then
    echo '⚠️  Script 00_test_complet_infrastructure_haproxy01.sh non trouvé'
    echo '   Vérifiez les scripts disponibles:'
    ls -la 00_test*.sh 2>/dev/null | head -10
    echo ''
    echo '   Scripts de test disponibles:'
    find . -name '*test*.sh' -type f 2>/dev/null | head -10
    exit 1
fi

# Rendre le script exécutable
chmod +x 00_test_complet_infrastructure_haproxy01.sh

echo '✅ Script trouvé et rendu exécutable'
echo ''
echo '🚀 Démarrage des tests...'
echo ''

# Exécuter le script de test
./00_test_complet_infrastructure_haproxy01.sh

echo ''
echo '=============================================================='
echo '  Tests terminés'
echo '=============================================================='
"@

Write-Host "🔌 Connexion à install-01..." -ForegroundColor Cyan
Write-Host "   ⚠️  Entrez le passphrase de la clé SSH quand demandé" -ForegroundColor Yellow
Write-Host ""

# Exécuter la commande
Invoke-Expression "$sshCmd `"$remoteScript`""

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Exécution terminée" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan

