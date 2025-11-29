# connect_install01_simple.ps1 - Connexion simple à install-01
# Usage: .\connect_install01_simple.ps1 "commande"
#        .\connect_install01_simple.ps1  # Session interactive
#
# Ce script utilise la nouvelle clé SSH sans passphrase
# Plus besoin de ssh-agent ou de passphrase !

param(
    [Parameter(Mandatory=$false)]
    [string]$Command = ""
)

$INSTALL_01_IP = "91.98.128.153"
$SSH_USER = "root"

# Se connecter directement (la clé est configurée dans ~/.ssh/config)
if ($Command) {
    ssh install-01 $Command
} else {
    ssh install-01
}

