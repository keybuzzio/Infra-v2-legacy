# ssh_install01_pageant.ps1 - Connexion a install-01 via Pageant et plink
# Usage: .\ssh_install01_pageant.ps1 "commande"
#        .\ssh_install01_pageant.ps1  # Session interactive
#
# Ce script utilise Pageant pour automatiser la connexion SSH
# Il convertit automatiquement la cle OpenSSH en .ppk si necessaire

param(
    [Parameter(Mandatory=$false)]
    [string]$Command = ""
)

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"

# Chemins
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$SSH_KEY = Join-Path $ProjectRoot "SSH\keybuzz_infra"
$SSH_KEY_PPK = Join-Path $ProjectRoot "SSH\keybuzz_infra.ppk"
$PASSPHRASE_FILE = Join-Path $ProjectRoot "SSH\passphrase.txt"

# Lire le passphrase
$passphrase = (Get-Content $PASSPHRASE_FILE -Raw).Trim()

# Verifier si plink est disponible
$plinkCommand = Get-Command plink -ErrorAction SilentlyContinue
if (-not $plinkCommand) {
    Write-Host "Plink n'est pas disponible. Installation de PuTTY requise." -ForegroundColor Red
    exit 1
}

# Verifier si puttygen est disponible
$puttygenCommand = Get-Command puttygen -ErrorAction SilentlyContinue

# Verifier si Pageant est en cours d'execution
$pageantProcess = Get-Process pageant -ErrorAction SilentlyContinue

if (-not $pageantProcess) {
    Write-Host "Pageant n'est pas en cours d'execution. Demarrage..." -ForegroundColor Yellow
    
    # Chercher Pageant
    $pageantPath = Get-Command pageant -ErrorAction SilentlyContinue
    if (-not $pageantPath) {
        $commonPaths = @(
            "$env:ProgramFiles\PuTTY\pageant.exe",
            "${env:ProgramFiles(x86)}\PuTTY\pageant.exe",
            "$env:LOCALAPPDATA\Programs\PuTTY\pageant.exe"
        )
        $pageantPath = $commonPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        
        if (-not $pageantPath) {
            Write-Host "Pageant introuvable. Veuillez installer PuTTY." -ForegroundColor Red
            exit 1
        }
    } else {
        $pageantPath = $pageantPath.Source
    }
    
    # Demarrer Pageant
    Start-Process -FilePath $pageantPath -WindowStyle Minimized
    Start-Sleep -Seconds 2
    
    Write-Host "Pageant demarre." -ForegroundColor Green
}

# Verifier si la cle .ppk existe, sinon la convertir
if (-not (Test-Path $SSH_KEY_PPK)) {
    Write-Host "Conversion de la cle OpenSSH en format .ppk..." -ForegroundColor Cyan
    
    if (-not $puttygenCommand) {
        Write-Host "Puttygen n'est pas disponible. Veuillez convertir manuellement la cle." -ForegroundColor Red
        Write-Host "Ou installer PuTTY complet avec puttygen." -ForegroundColor Yellow
        exit 1
    }
    
    # Convertir la cle OpenSSH en .ppk avec puttygen
    # puttygen keybuzz_infra -o keybuzz_infra.ppk -O private
    # Le passphrase sera demande lors de la conversion
    Write-Host "Conversion en cours... Vous devrez entrer le passphrase de la cle." -ForegroundColor Yellow
    $convertCmd = "puttygen `"$SSH_KEY`" -o `"$SSH_KEY_PPK`" -O private"
    Invoke-Expression $convertCmd
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Erreur lors de la conversion de la cle." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Cle convertie avec succes." -ForegroundColor Green
}

# Charger la cle dans Pageant
Write-Host "Chargement de la cle dans Pageant..." -ForegroundColor Cyan

# Creer un script temporaire pour charger la cle
$tempScript = Join-Path $env:TEMP "load_key_pageant.ps1"
$loadScript = @"
`$passphrase = '$passphrase'
`$pageantExe = Get-Command pageant -ErrorAction SilentlyContinue
if (`$pageantExe) {
    `$pageantPath = `$pageantExe.Source
} else {
    `$commonPaths = @(
        "`$env:ProgramFiles\PuTTY\pageant.exe",
        "`$env:ProgramFiles(x86)\PuTTY\pageant.exe",
        "`$env:LOCALAPPDATA\Programs\PuTTY\pageant.exe"
    )
    `$pageantPath = `$commonPaths | Where-Object { Test-Path `$_ } | Select-Object -First 1
}

# Charger la cle avec le passphrase
# Pageant ne peut pas etre charge directement avec passphrase en ligne de commande
# Il faut utiliser l'interface graphique ou un script wrapper
Start-Process -FilePath `$pageantPath -ArgumentList "`"$SSH_KEY_PPK`""
"@

Set-Content -Path $tempScript -Value $loadScript -Force

# Pour charger automatiquement dans Pageant, on peut utiliser une fenetre Pageant
# Mais la meilleure methode est de guider l'utilisateur
Write-Host ""
Write-Host "IMPORTANT: Chargez manuellement la cle dans Pageant:" -ForegroundColor Yellow
Write-Host "  1. Clic droit sur l'icone Pageant dans la barre des taches" -ForegroundColor Gray
Write-Host "  2. Selectionner 'Add Key'" -ForegroundColor Gray
Write-Host "  3. Choisir: $SSH_KEY_PPK" -ForegroundColor Gray
Write-Host "  4. Entrer le passphrase quand demande" -ForegroundColor Gray
Write-Host ""
Write-Host "Appuyez sur Entree apres avoir charge la cle..." -ForegroundColor Yellow
Read-Host

# Nettoyer
Remove-Item $tempScript -Force -ErrorAction SilentlyContinue

Write-Host "Connexion a install-01 via plink..." -ForegroundColor Cyan
Write-Host "   IP: $INSTALL_01_IP" -ForegroundColor Gray
Write-Host "   User: $SSH_USER" -ForegroundColor Gray
Write-Host ""

# Utiliser plink (qui utilisera automatiquement Pageant si la cle est chargee)
if ($Command) {
    Write-Host "Execution de la commande: $Command" -ForegroundColor Gray
    plink -ssh -batch -no-antispoof ${SSH_USER}@${INSTALL_01_IP} $Command
} else {
    Write-Host "Connexion interactive a install-01..." -ForegroundColor Cyan
    plink -ssh ${SSH_USER}@${INSTALL_01_IP}
}
