# ssh_exec.ps1 - Exécute une commande sur install-01 via SSH
# Usage: .\ssh_exec.ps1 "commande"

param(
    [Parameter(Mandatory=$true)]
    [string]$Command
)

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"

# Détecter la clé SSH
$SSH_KEY = ""
if (Test-Path "$env:USERPROFILE\.ssh\keybuzz_infra") {
    $SSH_KEY = "$env:USERPROFILE\.ssh\keybuzz_infra"
} elseif (Test-Path "$env:USERPROFILE\.ssh\id_ed25519") {
    $SSH_KEY = "$env:USERPROFILE\.ssh\id_ed25519"
} elseif (Test-Path "$env:USERPROFILE\.ssh\id_rsa") {
    $SSH_KEY = "$env:USERPROFILE\.ssh\id_rsa"
}

# Construire la commande SSH
$sshCmd = "ssh"
if ($SSH_KEY) {
    $sshCmd += " -i `"$SSH_KEY`""
}
$sshCmd += " -o StrictHostKeyChecking=accept-new"
$sshCmd += " ${SSH_USER}@${INSTALL_01_IP}"
$sshCmd += " `"$Command`""

Write-Host "Exécution sur install-01 : $Command" -ForegroundColor Cyan
Invoke-Expression $sshCmd


