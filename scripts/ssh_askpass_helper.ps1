# ssh_askpass_helper.ps1 - Helper pour ssh-add qui retourne le passphrase
# Ce script est appelé par ssh-add via SSH_ASKPASS

param(
    [Parameter(Mandatory=$false)]
    [string]$PassphraseFile = ""
)

if ($PassphraseFile -and (Test-Path $PassphraseFile)) {
    $passphrase = Get-Content $PassphraseFile -Raw | ForEach-Object { $_.Trim() }
    Write-Output $passphrase
} else {
    # Par défaut, chercher le fichier passphrase
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
    $passphraseFile = Join-Path $projectRoot "SSH\passphrase.txt"
    
    if (Test-Path $passphraseFile) {
        $passphrase = Get-Content $passphraseFile -Raw | ForEach-Object { $_.Trim() }
        Write-Output $passphrase
    }
}

