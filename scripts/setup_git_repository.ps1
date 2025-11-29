# setup_git_repository.ps1
# Script pour initialiser et configurer le dépôt Git pour KeyBuzz Infrastructure
#
# Usage:
#   .\setup_git_repository.ps1
#

$ErrorActionPreference = "Stop"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " Configuration du dépôt Git KeyBuzz Infrastructure" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Vérifier que Git est installé
Write-Host "[1] Vérification de Git..." -ForegroundColor Yellow
try {
    $gitVersion = git --version
    Write-Host "  [OK] Git installé : $gitVersion" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] Git n'est pas installé" -ForegroundColor Red
    Write-Host "  Installez Git depuis : https://git-scm.com/download/win" -ForegroundColor Yellow
    exit 1
}

# Naviguer vers le dossier racine
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

Write-Host ""
Write-Host "[2] Dossier de travail : $ProjectRoot" -ForegroundColor Yellow

# Vérifier si .gitignore existe
Write-Host ""
Write-Host "[3] Vérification de .gitignore..." -ForegroundColor Yellow
$gitignorePath = Join-Path $ProjectRoot ".gitignore"
if (Test-Path $gitignorePath) {
    Write-Host "  [OK] .gitignore existe" -ForegroundColor Green
} else {
    Write-Host "  [INFO] .gitignore non trouvé, création..." -ForegroundColor Yellow
    # Le .gitignore devrait être à la racine, vérifier dans Infra/
    $gitignoreInInfra = Join-Path (Join-Path $ProjectRoot "Infra") ".gitignore"
    if (Test-Path $gitignoreInInfra) {
        Copy-Item $gitignoreInInfra $gitignorePath
        Write-Host "  [OK] .gitignore copié depuis Infra/" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] .gitignore non trouvé, vous devrez le créer manuellement" -ForegroundColor Yellow
    }
}

# Vérifier si Git est déjà initialisé
Write-Host ""
Write-Host "[4] Vérification de l'initialisation Git..." -ForegroundColor Yellow
$gitDir = Join-Path $ProjectRoot ".git"
if (Test-Path $gitDir) {
    Write-Host "  [OK] Git déjà initialisé" -ForegroundColor Green
} else {
    Write-Host "  [INFO] Initialisation de Git..." -ForegroundColor Yellow
    git init
    Write-Host "  [OK] Git initialisé" -ForegroundColor Green
}

# Vérifier la configuration Git
Write-Host ""
Write-Host "[5] Vérification de la configuration Git..." -ForegroundColor Yellow
$userName = git config user.name
$userEmail = git config user.email

if ($userName) {
    Write-Host "  Nom d'utilisateur : $userName" -ForegroundColor Gray
} else {
    Write-Host "  [INFO] Nom d'utilisateur non configuré" -ForegroundColor Yellow
    $newName = Read-Host "  Entrez votre nom d'utilisateur Git"
    if ($newName) {
        git config --global user.name $newName
        Write-Host "  [OK] Nom d'utilisateur configuré" -ForegroundColor Green
    }
}

if ($userEmail) {
    Write-Host "  Email : $userEmail" -ForegroundColor Gray
} else {
    Write-Host "  [INFO] Email non configuré" -ForegroundColor Yellow
    $newEmail = Read-Host "  Entrez votre email Git"
    if ($newEmail) {
        git config --global user.email $newEmail
        Write-Host "  [OK] Email configuré" -ForegroundColor Green
    }
}

# Vérifier le remote
Write-Host ""
Write-Host "[6] Vérification du remote GitHub..." -ForegroundColor Yellow
$remotes = git remote -v
if ($remotes) {
    Write-Host "  Remotes configurés :" -ForegroundColor Gray
    $remotes | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
} else {
    Write-Host "  [INFO] Aucun remote configuré" -ForegroundColor Yellow
    $addRemote = Read-Host "  Voulez-vous ajouter le remote GitHub ? (O/N)"
    if ($addRemote -eq "O" -or $addRemote -eq "o") {
        $remoteUrl = Read-Host "  Entrez l'URL du dépôt (ex: https://github.com/keybuzzio/Infra.git)"
        if ($remoteUrl) {
            git remote add origin $remoteUrl
            Write-Host "  [OK] Remote ajouté" -ForegroundColor Green
        }
    }
}

# Afficher l'état
Write-Host ""
Write-Host "[7] État actuel du dépôt..." -ForegroundColor Yellow
git status --short | Select-Object -First 20 | ForEach-Object {
    Write-Host "  $_" -ForegroundColor Gray
}

$totalFiles = (git status --short | Measure-Object).Count
if ($totalFiles -gt 20) {
    Write-Host "  ... et $($totalFiles - 20) autres fichiers" -ForegroundColor Gray
}

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " Configuration terminée" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📋 Prochaines étapes :" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Vérifier les fichiers à commiter :" -ForegroundColor White
Write-Host "   git status" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Ajouter les fichiers :" -ForegroundColor White
Write-Host "   git add Infra/" -ForegroundColor Gray
Write-Host "   git add Context/  # Si vous voulez inclure Context.txt" -ForegroundColor Gray
Write-Host "   git add .gitignore" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Faire le premier commit :" -ForegroundColor White
Write-Host "   git commit -m 'Initial commit: Infrastructure KeyBuzz'" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Pousser vers GitHub :" -ForegroundColor White
Write-Host "   git push -u origin main" -ForegroundColor Gray
Write-Host ""
Write-Host "5. Sur install-01, cloner le dépôt :" -ForegroundColor White
Write-Host "   cd /opt" -ForegroundColor Gray
Write-Host "   git clone https://github.com/keybuzzio/Infra.git keybuzz-installer" -ForegroundColor Gray
Write-Host ""








