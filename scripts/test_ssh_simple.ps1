# test_ssh_simple.ps1 - Test simple de connexion SSH
# Ce script vous permettra d'entrer le passphrase manuellement

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$SSH_KEY = "C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra"

Write-Host "🔌 Test de connexion SSH à install-01" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠️  IMPORTANT: Vous devrez entrer le passphrase dans la fenêtre qui va s'ouvrir" -ForegroundColor Yellow
Write-Host ""
Write-Host "Appuyez sur Entrée pour continuer..."
Read-Host

# Exécuter SSH directement (vous pourrez entrer le passphrase)
$testCommand = "echo 'Connexion SSH reussie!' && hostname && whoami && date"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${INSTALL_01_IP}" $testCommand

