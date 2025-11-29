#!/usr/bin/env python3
"""
Script pour transférer les fichiers des images placeholder vers install-01
"""
import subprocess
import os

# Chemin local des fichiers
base_local = "Infra/scripts/10_platform/platform-images"
base_remote = "/opt/keybuzz-installer-v2/platform-images"

# Fichiers à transférer
files = [
    ("api/app.py", "api/app.py"),
    ("api/requirements.txt", "api/requirements.txt"),
    ("api/Dockerfile", "api/Dockerfile"),
    ("ui/index.html", "ui/index.html"),
    ("ui/Dockerfile", "ui/Dockerfile"),
    ("my/index.html", "my/index.html"),
    ("my/Dockerfile", "my/Dockerfile"),
]

ssh_key = os.path.expanduser("~/.ssh/keybuzz_auto")
host = "root@91.98.128.153"

for local_path, remote_path in files:
    local_full = os.path.join(base_local, local_path)
    remote_full = f"{base_remote}/{remote_path}"
    
    # Créer le répertoire distant si nécessaire
    remote_dir = os.path.dirname(remote_full)
    subprocess.run([
        "ssh", "-i", ssh_key, host,
        f"mkdir -p {remote_dir}"
    ], check=True)
    
    # Transférer le fichier
    subprocess.run([
        "scp", "-i", ssh_key,
        local_full,
        f"{host}:{remote_full}"
    ], check=True)
    
    print(f"✓ Transféré: {local_path}")

print("\n✅ Tous les fichiers ont été transférés")

