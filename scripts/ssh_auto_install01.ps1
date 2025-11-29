# ssh_auto_install01.ps1 - Connexion automatique a install-01 avec passphrase
# Usage: .\ssh_auto_install01.ps1 "commande"
#        .\ssh_auto_install01.ps1  # Session interactive
#
# Ce script automatise la connexion SSH en utilisant ssh-agent avec le passphrase

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
$PASSPHRASE_FILE = Join-Path $ProjectRoot "SSH\passphrase.txt"

# Lire le passphrase
$passphrase = (Get-Content $PASSPHRASE_FILE -Raw).Trim()

# Demarrer ssh-agent si necessaire
$agentService = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($agentService -and $agentService.Status -ne 'Running') {
    Write-Host "Demarrage du service ssh-agent..." -ForegroundColor Cyan
    Start-Service ssh-agent
    Start-Sleep -Seconds 2
}

# Creer un script temporaire qui retourne le passphrase
$tempAskPass = Join-Path $env:TEMP "ssh_askpass_$(Get-Random).ps1"
$askPassScript = @"
Write-Output '$passphrase'
"@
Set-Content -Path $tempAskPass -Value $askPassScript -Force

# Configurer SSH_ASKPASS
$env:SSH_ASKPASS = "powershell.exe"
$env:DISPLAY = "1"
$env:SSH_ASKPASS_REQUIRE = "force"

# Essayer de charger la cle dans ssh-agent
Write-Host "Chargement de la cle SSH dans ssh-agent..." -ForegroundColor Cyan
$null = & powershell.exe -ExecutionPolicy Bypass -File $tempAskPass | ssh-add $SSH_KEY 2>&1

# Nettoyer le script temporaire
Remove-Item $tempAskPass -Force -ErrorAction SilentlyContinue

# Construire la commande SSH
$sshCmd = "ssh -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"

if ($Command) {
    Write-Host "Execution sur install-01..." -ForegroundColor Cyan
    Write-Host "   Commande: $Command" -ForegroundColor Gray
    Invoke-Expression "$sshCmd `"$Command`""
} else {
    Write-Host "Connexion interactive a install-01..." -ForegroundColor Cyan
    Invoke-Expression $sshCmd
}

