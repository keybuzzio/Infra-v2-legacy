#!/usr/bin/env python3
"""
Génère une nouvelle clé SSH pour install-01
"""

import subprocess
import os
from datetime import datetime

# Chemin du répertoire .ssh
ssh_dir = os.path.expanduser("~/.ssh")
os.makedirs(ssh_dir, exist_ok=True)

# Nom de la clé
timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
key_name = f"keybuzz_install01_{timestamp}"
private_key_path = os.path.join(ssh_dir, key_name)
public_key_path = f"{private_key_path}.pub"

print("=" * 60)
print(" [KeyBuzz] Génération Nouvelle Clé SSH")
print("=" * 60)
print()

# Générer la clé
print(f"Génération de la clé SSH: {key_name}")
print()

try:
    # Générer la clé avec ssh-keygen
    result = subprocess.run(
        [
            "ssh-keygen",
            "-t", "ed25519",
            "-f", private_key_path,
            "-N", "",
            "-C", f"keybuzz-install01-{timestamp}"
        ],
        capture_output=True,
        text=True,
        check=True
    )
    
    print("✅ Clé SSH générée avec succès")
    print()
    
    # Lire la clé publique
    with open(public_key_path, 'r') as f:
        public_key = f.read().strip()
    
    print("=" * 60)
    print(" CLÉ PUBLIQUE (à copier sur install-01)")
    print("=" * 60)
    print()
    print(public_key)
    print()
    print("=" * 60)
    print()
    
    # Commande pour ajouter sur install-01
    print("COMMANDE POUR AJOUTER SUR install-01:")
    print("-" * 60)
    print()
    print("Depuis votre machine Windows:")
    print(f'  cat "{public_key_path}" | ssh root@install-01 "cat >> ~/.ssh/authorized_keys"')
    print()
    print("OU depuis install-01 (si vous êtes connecté):")
    print(f'  echo "{public_key}" >> ~/.ssh/authorized_keys')
    print('  chmod 600 ~/.ssh/authorized_keys')
    print()
    print("=" * 60)
    print()
    print(f"Clé privée: {private_key_path}")
    print(f"Clé publique: {public_key_path}")
    print()
    print("Pour utiliser cette clé:")
    print(f'  ssh -i "{private_key_path}" root@install-01')
    print()
    
except subprocess.CalledProcessError as e:
    print(f"❌ Erreur lors de la génération: {e}")
    print(e.stderr)
    exit(1)
except Exception as e:
    print(f"❌ Erreur: {e}")
    exit(1)


