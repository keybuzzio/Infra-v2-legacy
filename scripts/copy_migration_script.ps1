# Script pour copier le script de migration sur install-01
$scriptPath = "Infra\scripts\00_migration_k3s_vers_k8s.sh"
$fullPath = Join-Path (Get-Location) $scriptPath

if (Test-Path $fullPath) {
    Write-Host "Copie du script vers install-01..." -ForegroundColor Cyan
    $content = Get-Content $fullPath -Raw -Encoding UTF8
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
    
    ssh root@install-01 "echo '$encoded' | base64 -d > /opt/keybuzz-installer/scripts/00_migration_k3s_vers_k8s.sh && chmod +x /opt/keybuzz-installer/scripts/00_migration_k3s_vers_k8s.sh && echo 'Script copié avec succès'"
} else {
    Write-Host "Erreur: Fichier non trouvé: $fullPath" -ForegroundColor Red
    exit 1
}

