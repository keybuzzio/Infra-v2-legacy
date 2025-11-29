# ssh_exec_auto.ps1 - Exécute une commande sur install-01 avec passphrase automatique
# Usage: .\ssh_exec_auto.ps1 "commande"

param(
    [Parameter(Mandatory=$false)]
    [string]$Command = ""
)

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$PASSPHRASE_FILE = "$env:USERPROFILE\Mon Drive\keybuzzio\SSH\passphrase.txt"

# Vérifier que le fichier passphrase existe
if (-not (Test-Path $PASSPHRASE_FILE)) {
    Write-Host "❌ Fichier passphrase introuvable : $PASSPHRASE_FILE" -ForegroundColor Red
    exit 1
}

# Lire le passphrase
$passphrase = Get-Content $PASSPHRASE_FILE -Raw | ForEach-Object { $_.Trim() }

# Détecter la clé SSH
$SSH_KEY = ""
if (Test-Path "$env:USERPROFILE\.ssh\keybuzz_infra") {
    $SSH_KEY = "$env:USERPROFILE\.ssh\keybuzz_infra"
} elseif (Test-Path "$env:USERPROFILE\.ssh\id_ed25519") {
    $SSH_KEY = "$env:USERPROFILE\.ssh\id_ed25519"
} elseif (Test-Path "$env:USERPROFILE\.ssh\id_rsa") {
    $SSH_KEY = "$env:USERPROFILE\.ssh\id_rsa"
}

# Vérifier si sshpass est disponible (via WSL ou Git Bash)
$useSshpass = $false
if (Get-Command wsl -ErrorAction SilentlyContinue) {
    $useSshpass = $true
    $sshCmd = "wsl sshpass -p '$passphrase' ssh"
} elseif (Get-Command bash -ErrorAction SilentlyContinue) {
    $useSshpass = $true
    $sshCmd = "bash -c 'sshpass -p `"$passphrase`" ssh'"
}

if (-not $useSshpass) {
    Write-Host "⚠️  sshpass non disponible. Utilisation de SSH standard (vous devrez entrer le passphrase manuellement)" -ForegroundColor Yellow
    $sshCmd = "ssh"
    if ($SSH_KEY) {
        $sshCmd += " -i `"$SSH_KEY`""
    }
    $sshCmd += " -o StrictHostKeyChecking=accept-new"
    $sshCmd += " ${SSH_USER}@${INSTALL_01_IP}"
    
    if ($Command) {
        Write-Host "Exécution sur install-01 : $Command" -ForegroundColor Cyan
        Invoke-Expression "$sshCmd `"$Command`""
    } else {
        Write-Host "Connexion interactive à install-01..." -ForegroundColor Cyan
        Invoke-Expression $sshCmd
    }
} else {
    if ($SSH_KEY) {
        $sshCmd += " -i `"$SSH_KEY`""
    }
    $sshCmd += " -o StrictHostKeyChecking=accept-new"
    $sshCmd += " ${SSH_USER}@${INSTALL_01_IP}"
    
    if ($Command) {
        Write-Host "Exécution sur install-01 : $Command" -ForegroundColor Cyan
        Invoke-Expression "$sshCmd `"$Command`""
    } else {
        Write-Host "Connexion interactive à install-01..." -ForegroundColor Cyan
        Invoke-Expression $sshCmd
    }
}


