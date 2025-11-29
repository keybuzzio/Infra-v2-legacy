# exec_on_install01_auto.ps1 - Exécute des commandes sur install-01 avec passphrase automatique
# Ce script utilise sshpass via Git Bash ou ssh-agent pour automatiser la connexion
#
# Usage:
#   .\exec_on_install01_auto.ps1 "commande"
#   .\exec_on_install01_auto.ps1  # Session interactive

param(
    [Parameter(Mandatory=$false)]
    [string]$Command = ""
)

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"
$PASSPHRASE_FILE = "$PSScriptRoot\..\..\SSH\passphrase.txt"
$SSH_KEY = "$PSScriptRoot\..\..\SSH\keybuzz_infra"

# Vérifier les fichiers
if (-not (Test-Path $PASSPHRASE_FILE)) {
    Write-Host "❌ Fichier passphrase introuvable : $PASSPHRASE_FILE" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $SSH_KEY)) {
    Write-Host "❌ Clé SSH introuvable : $SSH_KEY" -ForegroundColor Red
    exit 1
}

# Lire le passphrase
$passphrase = Get-Content $PASSPHRASE_FILE -Raw | ForEach-Object { $_.Trim() }

# Méthode 1: Utiliser ssh-agent si disponible
$sshAgentRunning = Get-Process ssh-agent -ErrorAction SilentlyContinue
if ($sshAgentRunning) {
    Write-Host "✅ ssh-agent est actif, utilisation de la clé chargée" -ForegroundColor Green
    $sshCmd = "ssh"
    $sshCmd += " -i `"$SSH_KEY`""
    $sshCmd += " -o StrictHostKeyChecking=accept-new"
    $sshCmd += " ${SSH_USER}@${INSTALL_01_IP}"
    
    if ($Command) {
        Write-Host "🔌 Exécution sur install-01 : $Command" -ForegroundColor Cyan
        Invoke-Expression "$sshCmd `"$Command`""
    } else {
        Write-Host "🔌 Connexion interactive à install-01..." -ForegroundColor Cyan
        Invoke-Expression $sshCmd
    }
    exit 0
}

# Méthode 2: Utiliser Git Bash avec sshpass
$gitBash = Get-Command bash -ErrorAction SilentlyContinue
if ($gitBash) {
    Write-Host "✅ Git Bash détecté, utilisation de sshpass" -ForegroundColor Green
    
    # Convertir le chemin Windows en chemin Git Bash
    $bashKey = $SSH_KEY -replace '\\', '/' -replace '^C:', '/c' -replace '^([A-Z]):', '/$1'
    $bashKey = $bashKey.ToLower()
    
    # Vérifier si sshpass est disponible dans Git Bash
    $sshpassCheck = bash -c "which sshpass" 2>&1
    if ($LASTEXITCODE -eq 0) {
        # sshpass disponible, l'utiliser
        if ($Command) {
            $bashCmd = "sshpass -p '$passphrase' ssh -i '$bashKey' -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP} `"$Command`""
            Write-Host "🔌 Exécution sur install-01 : $Command" -ForegroundColor Cyan
            bash -c $bashCmd
        } else {
            $bashCmd = "sshpass -p '$passphrase' ssh -i '$bashKey' -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"
            Write-Host "🔌 Connexion interactive à install-01..." -ForegroundColor Cyan
            bash -c $bashCmd
        }
        exit 0
    } else {
        Write-Host "⚠️  sshpass non disponible dans Git Bash" -ForegroundColor Yellow
        Write-Host "   Installation de sshpass via apt-get (nécessite WSL) ou utilisation de SSH direct" -ForegroundColor Yellow
    }
}

# Méthode 3: Charger la clé dans ssh-agent pour cette session
Write-Host "📝 Tentative de chargement de la clé dans ssh-agent..." -ForegroundColor Yellow

# Démarrer ssh-agent si nécessaire
$sshAgentProcess = Get-Process ssh-agent -ErrorAction SilentlyContinue
if (-not $sshAgentProcess) {
    Write-Host "   Démarrage de ssh-agent..." -ForegroundColor Yellow
    Start-Service ssh-agent -ErrorAction SilentlyContinue
    if (-not (Get-Service ssh-agent -ErrorAction SilentlyContinue)) {
        Write-Host "   ⚠️  ssh-agent non disponible, utilisation de SSH direct" -ForegroundColor Yellow
    }
}

# Essayer de charger la clé avec ssh-add
$env:SSH_ASKPASS_REQUIRE = "never"
$passphraseFile = New-TemporaryFile
$passphrase | Out-File -FilePath $passphraseFile.FullName -NoNewline -Encoding ASCII
$env:SSH_ASKPASS = "powershell.exe -File `"$PSScriptRoot\ssh_askpass.ps1`" -PassphraseFile `"$passphraseFile.FullName`""

# Méthode 4: Utiliser expect via Git Bash (fallback)
Write-Host "📝 Utilisation de Git Bash avec expect-like functionality..." -ForegroundColor Yellow

$bashKey = $SSH_KEY -replace '\\', '/' -replace '^C:', '/c' -replace '^([A-Z]):', '/$1'
$bashKey = $bashKey.ToLower()

# Créer un script bash temporaire qui utilise expect ou sshpass
$bashScript = @"
#!/bin/bash
SSH_KEY='$bashKey'
PASSPHRASE='$passphrase'
INSTALL_01_IP='$INSTALL_01_IP'
SSH_USER='$SSH_USER'
COMMAND='$Command'

if command -v sshpass &> /dev/null; then
    if [ -n "\$COMMAND" ]; then
        sshpass -p "\$PASSPHRASE" ssh -i "\$SSH_KEY" -o StrictHostKeyChecking=accept-new \${SSH_USER}@\${INSTALL_01_IP} "\$COMMAND"
    else
        sshpass -p "\$PASSPHRASE" ssh -i "\$SSH_KEY" -o StrictHostKeyChecking=accept-new \${SSH_USER}@\${INSTALL_01_IP}
    fi
else
    echo "❌ sshpass non disponible. Installation..." 
    echo "   Vous pouvez installer sshpass via: apt-get install sshpass (dans WSL)"
    echo ""
    echo "   Connexion manuelle (vous devrez entrer le passphrase):"
    if [ -n "\$COMMAND" ]; then
        ssh -i "\$SSH_KEY" -o StrictHostKeyChecking=accept-new \${SSH_USER}@\${INSTALL_01_IP} "\$COMMAND"
    else
        ssh -i "\$SSH_KEY" -o StrictHostKeyChecking=accept-new \${SSH_USER}@\${INSTALL_01_IP}
    fi
fi
"@

$tempScript = [System.IO.Path]::GetTempFileName() + ".sh"
$bashScript | Out-File -FilePath $tempScript -Encoding ASCII -NoNewline

if ($Command) {
    Write-Host "🔌 Exécution sur install-01 : $Command" -ForegroundColor Cyan
    bash $tempScript
} else {
    Write-Host "🔌 Connexion interactive à install-01..." -ForegroundColor Cyan
    Write-Host "   ⚠️  Vous devrez entrer le passphrase une fois" -ForegroundColor Yellow
    bash $tempScript
}

# Nettoyer
Remove-Item $tempScript -ErrorAction SilentlyContinue
Remove-Item $passphraseFile.FullName -ErrorAction SilentlyContinue

