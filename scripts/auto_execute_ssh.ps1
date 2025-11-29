# auto_execute_ssh.ps1 - Exécute une commande SSH avec passphrase automatique
# Utilise plink (PuTTY) ou ssh avec expect

param(
    [Parameter(Mandatory=$true)]
    [string]$Command
)

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$SSH_KEY = "$PSScriptRoot\..\..\SSH\keybuzz_infra"
$PASSPHRASE_FILE = "$PSScriptRoot\..\..\SSH\passphrase.txt"

# Lire le passphrase
$passphrase = Get-Content $PASSPHRASE_FILE -Raw | ForEach-Object { $_.Trim() }

# Vérifier si plink est disponible (PuTTY)
$plinkPath = Get-Command plink -ErrorAction SilentlyContinue
if ($plinkPath) {
    Write-Host "Utilisation de plink (PuTTY)..." -ForegroundColor Cyan
    $plinkCmd = "plink.exe -ssh -i `"$SSH_KEY`" -batch ${SSH_USER}@${INSTALL_01_IP} `"$Command`""
    Invoke-Expression $plinkCmd
} else {
    # Utiliser ssh standard (nécessitera l'entrée manuelle du passphrase)
    Write-Host "Utilisation de ssh standard..." -ForegroundColor Yellow
    Write-Host "Vous devrez entrer le passphrase manuellement" -ForegroundColor Yellow
    $sshCmd = "ssh -i `"$SSH_KEY`" -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP} `"$Command`""
    Invoke-Expression $sshCmd
}


