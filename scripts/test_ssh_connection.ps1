# test_ssh_connection.ps1 - Test de connexion SSH à install-01
# Usage: .\test_ssh_connection.ps1

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Test de connexion SSH à install-01" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Test 1: Vérifier ssh-agent
Write-Host "1. Vérification de ssh-agent..." -ForegroundColor Yellow
$agent = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($agent -and $agent.Status -eq 'Running') {
    Write-Host "   ✅ ssh-agent est actif" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  ssh-agent n'est pas actif" -ForegroundColor Yellow
}

# Test 2: Vérifier les clés chargées
Write-Host ""
Write-Host "2. Vérification des clés SSH chargées..." -ForegroundColor Yellow
$keys = ssh-add -l 2>&1
if ($LASTEXITCODE -eq 0 -and $keys -notmatch "The agent has no identities") {
    Write-Host "   ✅ Clés chargées :" -ForegroundColor Green
    ssh-add -l | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
} else {
    Write-Host "   ⚠️  Aucune clé chargée" -ForegroundColor Yellow
    Write-Host "      Exécutez : .\setup_ssh_once.ps1" -ForegroundColor Gray
}

# Test 3: Vérifier la clé SSH
Write-Host ""
Write-Host "3. Vérification de la clé SSH..." -ForegroundColor Yellow
$SSH_KEY_PATH = "$PSScriptRoot\..\..\SSH\keybuzz_infra"
if (Test-Path $SSH_KEY_PATH) {
    Write-Host "   ✅ Clé trouvée : $SSH_KEY_PATH" -ForegroundColor Green
} else {
    Write-Host "   ❌ Clé introuvable : $SSH_KEY_PATH" -ForegroundColor Red
}

# Test 4: Test de connexion
Write-Host ""
Write-Host "4. Test de connexion..." -ForegroundColor Yellow
$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"

$testResult = ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 ${SSH_USER}@${INSTALL_01_IP} "echo 'Connexion réussie!'" 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ Connexion réussie !" -ForegroundColor Green
    Write-Host "      $testResult" -ForegroundColor Gray
} else {
    Write-Host "   ❌ Échec de la connexion" -ForegroundColor Red
    Write-Host "      $testResult" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   Solutions possibles :" -ForegroundColor Yellow
    Write-Host "      - Exécutez : .\setup_ssh_once.ps1" -ForegroundColor Gray
    Write-Host "      - Vérifiez votre connexion internet" -ForegroundColor Gray
    Write-Host "      - Vérifiez que le serveur est accessible" -ForegroundColor Gray
}

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
