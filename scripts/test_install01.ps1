# test_install01.ps1 - Connexion et test simple pour vérifier la configuration

$SSH_KEY = Resolve-Path "..\..\SSH\keybuzz_infra"
Write-Host ""
Write-Host "Connexion a install-01..." -ForegroundColor Cyan
Write-Host ""
Write-Host ">>> VOUS ALLEZ DEVOIR ENTRER LE PASSPHRASE MAINTENANT <<<" -ForegroundColor Yellow
Write-Host "   Tapez votre passphrase (invisible) puis appuyez sur Entree" -ForegroundColor Yellow
Write-Host ""
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new root@91.98.128.153 "hostname && whoami && pwd && cd /opt/keybuzz-installer/scripts && ls -la 00_test*.sh 2>/dev/null | head -3 || echo 'Scripts de test non trouves'"

