# export_conversation_files.ps1
# Script pour exporter tous les fichiers créés/modifiés dans cette conversation
#
# Usage:
#   .\export_conversation_files.ps1
#

$ErrorActionPreference = "Stop"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " Export des fichiers de la conversation" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Dossier de travail
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ExportDir = Join-Path $ProjectRoot "EXPORT_CONVERSATION_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

Write-Host "[1] Création du dossier d'export..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $ExportDir -Force | Out-Null
Write-Host "  Dossier : $ExportDir" -ForegroundColor Gray

# Liste des fichiers à exporter
$FilesToExport = @(
    # Guides
    "Infra\SOLUTION_AUTHENTIFICATION_AUTOMATIQUE.md",
    "Infra\GUIDE_ACCES_FICHIERS_CODE_SERVER.md",
    "Infra\GUIDE_SYNCHRONISATION_GITHUB.md",
    "Infra\GUIDE_IA_SUR_INSTALL01.md",
    "Infra\RECAP_CONVERSATION_CODE_SERVER_GITHUB.md",
    "Infra\CHECKLIST_REPRISE_TRAVAIL.md",
    
    # Scripts Code-Server
    "Infra\scripts\00_install_code_server.sh",
    "Infra\scripts\00_fix_code_server_download.sh",
    "Infra\scripts\00_finish_code_server_installation.sh",
    "Infra\scripts\00_find_and_install_code_server.sh",
    "Infra\scripts\00_verify_and_fix_code_server.sh",
    
    # Scripts Git
    "Infra\scripts\setup_git_repository.ps1",
    
    # Configuration
    ".gitignore"
)

Write-Host ""
Write-Host "[2] Export des fichiers..." -ForegroundColor Yellow

$ExportedCount = 0
$MissingCount = 0

foreach ($File in $FilesToExport) {
    $SourcePath = Join-Path $ProjectRoot $File
    
    if (Test-Path $SourcePath) {
        $DestPath = Join-Path $ExportDir $File
        $DestDir = Split-Path $DestPath -Parent
        
        # Créer le dossier de destination si nécessaire
        if (-not (Test-Path $DestDir)) {
            New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
        }
        
        # Copier le fichier
        Copy-Item $SourcePath $DestPath -Force
        Write-Host "  [OK] $File" -ForegroundColor Green
        $ExportedCount++
    } else {
        Write-Host "  [MANQUANT] $File" -ForegroundColor Yellow
        $MissingCount++
    }
}

Write-Host ""
Write-Host "[3] Création du fichier récapitulatif..." -ForegroundColor Yellow

$RecapContent = @"
# Export de la conversation - Code-Server et GitHub

**Date d'export** : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Dossier d'export** : $ExportDir

## Fichiers exportés

### Guides ($ExportedCount fichiers)
- SOLUTION_AUTHENTIFICATION_AUTOMATIQUE.md
- GUIDE_ACCES_FICHIERS_CODE_SERVER.md
- GUIDE_SYNCHRONISATION_GITHUB.md
- GUIDE_IA_SUR_INSTALL01.md
- RECAP_CONVERSATION_CODE_SERVER_GITHUB.md
- CHECKLIST_REPRISE_TRAVAIL.md

### Scripts Code-Server
- 00_install_code_server.sh
- 00_fix_code_server_download.sh
- 00_finish_code_server_installation.sh
- 00_find_and_install_code_server.sh
- 00_verify_and_fix_code_server.sh

### Scripts Git
- setup_git_repository.ps1

### Configuration
- .gitignore

## Informations importantes

### Code-Server sur install-01
- **URL** : http://91.98.128.153:8080
- **Mot de passe** : Voir /opt/code-server-data/config.yaml
- **Workspace** : /opt/code-server-data/workspace

### Pour reprendre le travail
1. Lire : RECAP_CONVERSATION_CODE_SERVER_GITHUB.md
2. Suivre : CHECKLIST_REPRISE_TRAVAIL.md
3. Consulter les guides selon le besoin

## Fichiers manquants
$(
    if ($MissingCount -gt 0) {
        "Certains fichiers n'ont pas été trouvés lors de l'export."
    } else {
        "Tous les fichiers ont été exportés avec succès."
    }
)
"@

$RecapPath = Join-Path $ExportDir "README_EXPORT.md"
$RecapContent | Out-File -FilePath $RecapPath -Encoding UTF8

Write-Host "  [OK] README_EXPORT.md créé" -ForegroundColor Green

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " Export terminé" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📁 Dossier d'export : $ExportDir" -ForegroundColor Yellow
Write-Host "📄 Fichiers exportés : $ExportedCount" -ForegroundColor Green
if ($MissingCount -gt 0) {
    Write-Host "⚠️  Fichiers manquants : $MissingCount" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "📋 Pour reprendre le travail :" -ForegroundColor Cyan
Write-Host "   1. Lire : RECAP_CONVERSATION_CODE_SERVER_GITHUB.md" -ForegroundColor White
Write-Host "   2. Suivre : CHECKLIST_REPRISE_TRAVAIL.md" -ForegroundColor White
Write-Host ""








