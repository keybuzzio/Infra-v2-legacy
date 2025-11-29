# rebuild_complete_infrastructure_windows.ps1
# Script PowerShell pour lancer le rebuild complet depuis Windows
#
# Ce script :
#   1. Copie le script bash sur install-01
#   2. Lance le script de rebuild complet
#   3. Affiche la progression
#

$ErrorActionPreference = "Stop"

# Configuration
$INSTALL_01_IP = "91.98.128.153"
$SCRIPT_PATH = "Infra\scripts\00_rebuild_complete_infrastructure.sh"
$REMOTE_SCRIPT_PATH = "/opt/keybuzz-installer/scripts/00_rebuild_complete_infrastructure.sh"

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  REBUILD COMPLET INFRASTRUCTURE" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

# Vérifier que le script existe
if (-not (Test-Path $SCRIPT_PATH)) {
    Write-Host "[ERREUR] Script non trouvé : $SCRIPT_PATH" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Copie du script sur install-01..." -ForegroundColor Yellow

# Lire le contenu du script
$content = Get-Content $SCRIPT_PATH -Raw -Encoding UTF8

# Encoder en base64
$encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))

# Copier sur install-01
try {
    $result = ssh root@$INSTALL_01_IP "echo '$encoded' | base64 -d > $REMOTE_SCRIPT_PATH && chmod +x $REMOTE_SCRIPT_PATH && echo 'OK'"
    
    if ($result -match "OK") {
        Write-Host "[OK] Script copié sur install-01" -ForegroundColor Green
    } else {
        Write-Host "[ERREUR] Échec copie du script" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "[ERREUR] Impossible de copier le script : $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[INFO] Lancement du script de rebuild..." -ForegroundColor Yellow
Write-Host ""
Write-Host "ATTENTION : Cette opération va :" -ForegroundColor Yellow
Write-Host "  - Démontrer tous les volumes" -ForegroundColor Yellow
Write-Host "  - Rebuild tous les serveurs (sauf install-01 et backn8n)" -ForegroundColor Yellow
Write-Host "  - Formater les volumes en XFS" -ForegroundColor Yellow
Write-Host "  - Monter les volumes" -ForegroundColor Yellow
Write-Host "  - Propager les clés SSH" -ForegroundColor Yellow
Write-Host ""
Write-Host "Cela peut prendre 30-60 minutes selon le nombre de serveurs." -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Continuer ? (yes/NO)"
if ($confirm -ne "yes") {
    Write-Host "[INFO] Annulé" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "[INFO] Connexion à install-01 et lancement du script..." -ForegroundColor Cyan
Write-Host ""

# Lancer le script en mode interactif
ssh -t root@$INSTALL_01_IP "cd /opt/keybuzz-installer/scripts && bash $REMOTE_SCRIPT_PATH"

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  REBUILD TERMINE" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""


