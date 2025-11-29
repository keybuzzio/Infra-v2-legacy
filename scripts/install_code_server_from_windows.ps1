# install_code_server_from_windows.ps1
# Script pour transférer et installer code-server sur install-01
# 
# Usage:
#   .\install_code_server_from_windows.ps1
#
# IMPORTANT: Vous devrez entrer la passphrase SSH une fois

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$SSH_KEY = "C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra"
$SCRIPT_PATH = "C:\Users\ludov\Mon Drive\keybuzzio\Infra\scripts\00_install_code_server.sh"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " Installation Code-Server sur install-01" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Vérifier que le script existe
if (-not (Test-Path $SCRIPT_PATH)) {
    Write-Host "ERREUR: Script non trouvé : $SCRIPT_PATH" -ForegroundColor Red
    exit 1
}

Write-Host "[1] Transfert du script vers install-01..." -ForegroundColor Yellow
scp -i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null `
    $SCRIPT_PATH `
    "${SSH_USER}@${INSTALL_01_IP}:/tmp/00_install_code_server.sh"

if ($LASTEXITCODE -ne 0) {
    Write-Host "  [FAIL] Échec du transfert" -ForegroundColor Red
    Write-Host "  Vous devrez peut-être entrer la passphrase SSH" -ForegroundColor Yellow
    exit 1
}

Write-Host "  [OK] Script transféré" -ForegroundColor Green
Write-Host ""

Write-Host "[2] Exécution de l'installation sur install-01..." -ForegroundColor Yellow
Write-Host "  (Vous devrez peut-être entrer la passphrase SSH)" -ForegroundColor Gray
Write-Host ""

ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null `
    "${SSH_USER}@${INSTALL_01_IP}" `
    "chmod +x /tmp/00_install_code_server.sh && bash /tmp/00_install_code_server.sh"

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Green
    Write-Host " [OK] Installation terminée" -ForegroundColor Green
    Write-Host "==============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "📋 Pour accéder à Code-Server :" -ForegroundColor Cyan
    Write-Host "   1. Ouvrez votre navigateur" -ForegroundColor White
    Write-Host "   2. Allez sur : http://${INSTALL_01_IP}:8080" -ForegroundColor White
    Write-Host "   3. Entrez le mot de passe affiché ci-dessus" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Red
    Write-Host " [FAIL] Échec de l'installation" -ForegroundColor Red
    Write-Host "==============================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Vérifiez les logs sur install-01 :" -ForegroundColor Yellow
    Write-Host "   ssh -i `"$SSH_KEY`" ${SSH_USER}@${INSTALL_01_IP}" -ForegroundColor Gray
    Write-Host "   journalctl -u code-server -f" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

