# transfert_et_execute_tests.ps1 - Transfère et exécute les tests sur install-01
# Usage: .\transfert_et_execute_tests.ps1

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$SSH_KEY = "$PSScriptRoot\..\..\SSH\keybuzz_infra"
$TEST_SCRIPT = "$PSScriptRoot\00_test_complet_infrastructure_haproxy01.sh"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Transfert et exécution des tests sur install-01" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Vérifier la clé SSH
if (-not (Test-Path $SSH_KEY)) {
    Write-Host "❌ Clé SSH introuvable : $SSH_KEY" -ForegroundColor Red
    exit 1
}

# Vérifier le script de test
if (-not (Test-Path $TEST_SCRIPT)) {
    Write-Host "❌ Script de test introuvable : $TEST_SCRIPT" -ForegroundColor Red
    exit 1
}

Write-Host "📋 Étapes :" -ForegroundColor Yellow
Write-Host "  1. Transfert du script de test sur install-01" -ForegroundColor Yellow
Write-Host "  2. Connexion à install-01 et exécution du script" -ForegroundColor Yellow
Write-Host ""

# Étape 1: Transférer le script via SCP
Write-Host "📤 Transfert du script sur install-01..." -ForegroundColor Cyan
Write-Host "   ⚠️  Entrez le passphrase de la clé SSH quand demandé" -ForegroundColor Yellow
Write-Host ""

$scpCmd = "scp -i `"$SSH_KEY`" -o StrictHostKeyChecking=accept-new `"$TEST_SCRIPT`" ${SSH_USER}@${INSTALL_01_IP}:/opt/keybuzz-installer/scripts/"

try {
    Invoke-Expression $scpCmd
    Write-Host ""
    Write-Host "✅ Script transféré avec succès" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host ""
    Write-Host "❌ Erreur lors du transfert : $_" -ForegroundColor Red
    Write-Host "   Vérifiez que le répertoire /opt/keybuzz-installer/scripts existe sur install-01" -ForegroundColor Yellow
    exit 1
}

# Étape 2: Exécuter le script sur install-01
Write-Host "🚀 Exécution du script de test sur install-01..." -ForegroundColor Cyan
Write-Host ""

$sshCmd = "ssh -i `"$SSH_KEY`" -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"

$remoteCommand = @"
cd /opt/keybuzz-installer/scripts
chmod +x 00_test_complet_infrastructure_haproxy01.sh
./00_test_complet_infrastructure_haproxy01.sh
"@

Invoke-Expression "$sshCmd `"$remoteCommand`""

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Exécution terminée" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan

