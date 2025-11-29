# ssh_pageant_install01.ps1 - Connexion a install-01 via Pageant
# Usage: .\ssh_pageant_install01.ps1 "commande"
#        .\ssh_pageant_install01.ps1  # Session interactive
#
# Ce script utilise Pageant pour automatiser la connexion SSH

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
$SSH_KEY_PUB = Join-Path $ProjectRoot "SSH\keybuzz_infra.pub"

# Verifier si plink est disponible
$plinkCommand = Get-Command plink -ErrorAction SilentlyContinue
if (-not $plinkCommand) {
    Write-Host "Plink n'est pas disponible. Installation de PuTTY requise." -ForegroundColor Red
    exit 1
}

# Verifier si Pageant est en cours d'execution
$pageantProcess = Get-Process pageant -ErrorAction SilentlyContinue

if (-not $pageantProcess) {
    Write-Host "Pageant n'est pas en cours d'execution" -ForegroundColor Yellow
    Write-Host "Demarrage de Pageant..." -ForegroundColor Cyan
    
    # Chercher Pageant dans le PATH ou les emplacements habituels
    $pageantPath = Get-Command pageant -ErrorAction SilentlyContinue
    if (-not $pageantPath) {
        # Essayer les emplacements communs
        $commonPaths = @(
            "$env:ProgramFiles\PuTTY\pageant.exe",
            "${env:ProgramFiles(x86)}\PuTTY\pageant.exe",
            "$env:LOCALAPPDATA\Programs\PuTTY\pageant.exe"
        )
        
        $pageantPath = $commonPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        
        if (-not $pageantPath) {
            Write-Host "Pageant introuvable. Veuillez installer PuTTY ou demarrer Pageant manuellement." -ForegroundColor Red
            exit 1
        }
    } else {
        $pageantPath = $pageantPath.Source
    }
    
    # Demarrer Pageant
    Start-Process -FilePath $pageantPath -WindowStyle Minimized
    Start-Sleep -Seconds 2
    
    Write-Host "Pageant demarre. Vous devez maintenant charger la cle SSH dans Pageant." -ForegroundColor Yellow
    Write-Host "Cliquez sur l'icone Pageant dans la barre des taches et ajoutez la cle :" -ForegroundColor Yellow
    Write-Host "  $SSH_KEY" -ForegroundColor Gray
    Write-Host ""
    Write-Host "OU utilisez la commande suivante pour convertir et charger la cle automatiquement:" -ForegroundColor Cyan
    Write-Host "  puttygen $SSH_KEY -o keybuzz_infra.ppk" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Appuyez sur Entree apres avoir charge la cle dans Pageant..." -ForegroundColor Yellow
    Read-Host
}

# Verifier si Pageant est maintenant actif
$pageantProcess = Get-Process pageant -ErrorAction SilentlyContinue
if (-not $pageantProcess) {
    Write-Host "Pageant n'est toujours pas actif. Connexion impossible." -ForegroundColor Red
    exit 1
}

Write-Host "Pageant est actif. Utilisation de plink pour la connexion..." -ForegroundColor Green
Write-Host "Connexion a install-01..." -ForegroundColor Cyan
Write-Host "   IP: $INSTALL_01_IP" -ForegroundColor Gray
Write-Host "   User: $SSH_USER" -ForegroundColor Gray
Write-Host ""

# Construire la commande plink
if ($Command) {
    Write-Host "Execution de la commande: $Command" -ForegroundColor Gray
    plink -ssh -batch -no-antispoof ${SSH_USER}@${INSTALL_01_IP} $Command
} else {
    Write-Host "Connexion interactive a install-01..." -ForegroundColor Cyan
    plink -ssh ${SSH_USER}@${INSTALL_01_IP}
}

