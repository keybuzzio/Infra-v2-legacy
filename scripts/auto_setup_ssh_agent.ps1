# auto_setup_ssh_agent.ps1 - Configure automatiquement ssh-agent
# Usage: .\auto_setup_ssh_agent.ps1
# Ce script configure ssh-agent et charge la clé SSH automatiquement

$SSH_KEY = "$PSScriptRoot\..\..\SSH\keybuzz_infra"
$PASSPHRASE_FILE = "$PSScriptRoot\..\..\SSH\passphrase.txt"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  Configuration automatique ssh-agent" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Vérifier la clé SSH
if (-not (Test-Path $SSH_KEY)) {
    Write-Host "❌ Clé SSH introuvable : $SSH_KEY" -ForegroundColor Red
    exit 1
}

# Vérifier le fichier passphrase
if (-not (Test-Path $PASSPHRASE_FILE)) {
    Write-Host "❌ Fichier passphrase introuvable : $PASSPHRASE_FILE" -ForegroundColor Red
    exit 1
}

# Étape 1: Démarrer ssh-agent
Write-Host "📋 Étape 1: Démarrage de ssh-agent..." -ForegroundColor Yellow

$sshAgentService = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($sshAgentService) {
    if ($sshAgentService.Status -ne 'Running') {
        Write-Host "   Démarrage du service ssh-agent..." -ForegroundColor Yellow
        Start-Service ssh-agent
        Start-Sleep -Seconds 2
        Write-Host "   ✅ Service ssh-agent démarré" -ForegroundColor Green
    } else {
        Write-Host "   ✅ Service ssh-agent déjà actif" -ForegroundColor Green
    }
} else {
    Write-Host "   ⚠️  Service ssh-agent non disponible" -ForegroundColor Yellow
}

Write-Host ""

# Étape 2: Vérifier si la clé est déjà chargée
Write-Host "📋 Étape 2: Vérification des clés chargées..." -ForegroundColor Yellow

$keysLoaded = ssh-add -l 2>&1
if ($LASTEXITCODE -eq 0) {
    # Analyser la sortie pour voir si notre clé est chargée
    $keyName = Split-Path $SSH_KEY -Leaf
    if ($keysLoaded -match $keyName -or $keysLoaded -match "keybuzz") {
        Write-Host "   ✅ Clé SSH déjà chargée dans ssh-agent" -ForegroundColor Green
        Write-Host ""
        Write-Host "🎉 Configuration terminée - Clé déjà chargée !" -ForegroundColor Green
        exit 0
    }
    
    $keyCount = ($keysLoaded -split "`n" | Where-Object { $_ -match "^\d+\s" }).Count
    Write-Host "   ℹ️  $keyCount clé(s) déjà chargée(s)" -ForegroundColor Cyan
} else {
    Write-Host "   ℹ️  Aucune clé chargée actuellement" -ForegroundColor Cyan
}

Write-Host ""

# Étape 3: Lire le passphrase
Write-Host "📋 Étape 3: Chargement du passphrase..." -ForegroundColor Yellow

$passphrase = Get-Content $PASSPHRASE_FILE -Raw | ForEach-Object { $_.Trim() }
if ([string]::IsNullOrWhiteSpace($passphrase)) {
    Write-Host "   ❌ Passphrase vide ou invalide" -ForegroundColor Red
    exit 1
}

Write-Host "   ✅ Passphrase chargé depuis le fichier" -ForegroundColor Green
Write-Host ""

# Étape 4: Charger la clé dans ssh-agent
Write-Host "📋 Étape 4: Chargement de la clé SSH dans ssh-agent..." -ForegroundColor Yellow
Write-Host "   Méthode: Utilisation de Start-Process avec input redirection" -ForegroundColor Cyan

# Créer un fichier temporaire avec le passphrase
$tempPassFile = [System.IO.Path]::GetTempFileName()
$passphrase | Out-File -FilePath $tempPassFile -Encoding ASCII -NoNewline

# Méthode 1: Essayer avec Start-Process et RedirectStandardInput
Write-Host "   Tentative de chargement automatique..." -ForegroundColor Cyan

$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = "ssh-add"
$processInfo.Arguments = "`"$SSH_KEY`""
$processInfo.UseShellExecute = $false
$processInfo.RedirectStandardInput = $true
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.CreateNoWindow = $true

try {
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null
    
    # Envoyer le passphrase via stdin
    $process.StandardInput.WriteLine($passphrase)
    $process.StandardInput.Close()
    
    # Attendre un peu pour que le processus traite l'input
    Start-Sleep -Milliseconds 500
    
    $output = $process.StandardOutput.ReadToEnd()
    $error = $process.StandardError.ReadToEnd()
    
    # Attendre que le processus se termine ou timeout
    if (-not $process.WaitForExit(5000)) {
        $process.Kill()
        Write-Host "   ⚠️  Timeout lors du chargement" -ForegroundColor Yellow
    }
    
    if ($process.ExitCode -eq 0 -or $output -match "Identity added") {
        Write-Host "   ✅ Clé SSH chargée avec succès dans ssh-agent" -ForegroundColor Green
        $success = $true
    } else {
        Write-Host "   ⚠️  Méthode automatique échouée (code: $($process.ExitCode))" -ForegroundColor Yellow
        if ($error) {
            Write-Host "   Erreur: $error" -ForegroundColor Red
        }
        $success = $false
    }
} catch {
    Write-Host "   ⚠️  Erreur lors du chargement automatique: $_" -ForegroundColor Yellow
    $success = $false
}

# Si la méthode automatique a échoué, essayer avec Git Bash
if (-not $success) {
    $gitBash = Get-Command bash -ErrorAction SilentlyContinue
    if ($gitBash) {
        Write-Host "   Tentative avec Git Bash..." -ForegroundColor Cyan
        
        # Convertir les chemins pour Git Bash
        $bashKey = $SSH_KEY -replace '\\', '/' -replace '^C:', '/c' -replace '^([A-Z]):', '/$1'
        $bashKey = $bashKey.ToLower()
        
        # Créer un script bash temporaire
        $bashScriptContent = @"
#!/bin/bash
SSH_KEY='$bashKey'
PASSPHRASE='$passphrase'

# Utiliser echo pour passer le passphrase à ssh-add
echo "$PASSPHRASE" | ssh-add "$SSH_KEY" 2>&1
exit `$?
"@

        $tempBashScript = [System.IO.Path]::GetTempFileName() + ".sh"
        $bashScriptContent | Out-File -FilePath $tempBashScript -Encoding ASCII -NoNewline
        
        $bashResult = bash $tempBashScript 2>&1
        
        if ($LASTEXITCODE -eq 0 -or $bashResult -match "Identity added") {
            Write-Host "   ✅ Clé SSH chargée avec succès via Git Bash" -ForegroundColor Green
            $success = $true
        } else {
            Write-Host "   ⚠️  Échec via Git Bash" -ForegroundColor Yellow
        }
        
        Remove-Item $tempBashScript -ErrorAction SilentlyContinue
    }
}

# Si toutes les méthodes automatiques ont échoué, demander manuellement
if (-not $success) {
    Write-Host ""
    Write-Host "   ⚠️  Chargement automatique impossible" -ForegroundColor Yellow
    Write-Host "   Veuillez charger la clé manuellement:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   ssh-add `"$SSH_KEY`"" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   (Entrez le passphrase quand demandé)" -ForegroundColor Yellow
    Write-Host ""
    
    # Proposer de le faire maintenant
    $response = Read-Host "Voulez-vous charger la clé maintenant ? (O/N)"
    if ($response -eq "O" -or $response -eq "o" -or $response -eq "Y" -or $response -eq "y") {
        ssh-add $SSH_KEY
        $success = $true
    }
}

Write-Host ""

# Verification finale
if ($success) {
    Write-Host "Verification finale..." -ForegroundColor Yellow
    $finalCheck = ssh-add -l 2>&1
    if ($LASTEXITCODE -eq 0) {
        $keyName = Split-Path $SSH_KEY -Leaf
        if ($finalCheck -match $keyName -or $finalCheck -match "keybuzz") {
            Write-Host "   Cle SSH confirmee chargee dans ssh-agent" -ForegroundColor Green
            Write-Host ""
            Write-Host "Configuration terminee avec succes !" -ForegroundColor Green
            Write-Host "   Vous pouvez maintenant vous connecter sans entrer le passphrase" -ForegroundColor Green
        } else {
            Write-Host "   Cle non trouvee dans la liste, mais chargement semble reussi" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   Attention: Impossible de verifier les cles chargees" -ForegroundColor Yellow
    }
}

# Nettoyer
Remove-Item $tempPassFile -ErrorAction SilentlyContinue

Write-Host ""
