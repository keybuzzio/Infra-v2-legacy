#!/usr/bin/env python3
"""
Script Python pour exécuter la finalisation du Module 11 via SSH
"""

import subprocess
import sys
import time
import os

SSH_KEY = os.path.expanduser("~/.ssh/keybuzz_auto")
HOST = "root@91.98.128.153"
SCRIPT_PATH = "/opt/keybuzz-installer-v2/scripts/11_support_chatwoot/finaliser_module11.sh"

def run_ssh_command(command, timeout=None):
    """Exécute une commande SSH et retourne la sortie"""
    cmd = ["ssh", "-i", SSH_KEY, "-o", "StrictHostKeyChecking=no", 
           "-o", "ConnectTimeout=10", HOST, command]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "Timeout"
    except Exception as e:
        return -1, "", str(e)

def main():
    print("=" * 60)
    print(" [KeyBuzz] Module 11 - Finalisation via Python")
    print("=" * 60)
    print()
    
    # Étape 1 : Vérifier la connexion
    print("1. Vérification de la connexion SSH...")
    code, out, err = run_ssh_command("echo 'OK'", timeout=10)
    if code != 0:
        print(f"❌ Erreur de connexion: {err}")
        return 1
    print("✅ Connexion OK")
    print()
    
    # Étape 2 : Transférer le script si nécessaire
    print("2. Vérification du script sur le serveur...")
    code, out, err = run_ssh_command(f"test -f {SCRIPT_PATH} && echo 'EXISTS' || echo 'NOT_FOUND'")
    if "NOT_FOUND" in out:
        print("⚠️ Script non trouvé, création...")
        # Le script devrait déjà être là, mais on peut le recréer
        print("   (Le script devrait déjà être présent)")
    else:
        print("✅ Script trouvé")
    print()
    
    # Étape 3 : Exécuter le script en arrière-plan et suivre les logs
    print("3. Lancement du script de finalisation...")
    print("   (Le script s'exécute en arrière-plan)")
    print()
    
    # Lancer le script en arrière-plan avec redirection vers un log
    log_file = "/tmp/module11_finalisation.log"
    command = f"bash {SCRIPT_PATH} > {log_file} 2>&1 & echo $!"
    code, out, err = run_ssh_command(command, timeout=30)
    
    if code != 0:
        print(f"❌ Erreur lors du lancement: {err}")
        return 1
    
    pid = out.strip()
    print(f"✅ Script lancé (PID: {pid})")
    print(f"   Log: {log_file}")
    print()
    
    # Étape 4 : Suivre les logs
    print("4. Suivi de l'exécution (appuyez sur Ctrl+C pour arrêter le suivi)...")
    print("=" * 60)
    print()
    
    last_size = 0
    max_wait = 1200  # 20 minutes max
    start_time = time.time()
    
    try:
        while time.time() - start_time < max_wait:
            # Lire les logs
            code, out, err = run_ssh_command(f"tail -c +{last_size} {log_file} 2>/dev/null || cat {log_file}", timeout=10)
            if out:
                print(out, end='', flush=True)
                last_size += len(out.encode('utf-8'))
            
            # Vérifier si le processus est toujours en cours
            code, out, err = run_ssh_command(f"ps -p {pid} > /dev/null 2>&1 && echo 'RUNNING' || echo 'DONE'", timeout=10)
            if "DONE" in out:
                print()
                print("=" * 60)
                print("✅ Script terminé")
                break
            
            time.sleep(5)
            
    except KeyboardInterrupt:
        print()
        print("⚠️ Suivi interrompu par l'utilisateur")
        print(f"   Le script continue d'exécution sur le serveur (PID: {pid})")
        print(f"   Vérifiez les logs avec: ssh {HOST} 'tail -f {log_file}'")
        return 0
    
    # Étape 5 : Afficher les logs finaux
    print()
    print("5. Logs finaux:")
    print("=" * 60)
    code, out, err = run_ssh_command(f"cat {log_file}", timeout=30)
    if out:
        print(out)
    print()
    
    # Étape 6 : Vérifier l'état final
    print("6. Vérification de l'état final...")
    print("=" * 60)
    
    checks = [
        ("Jobs", "kubectl get jobs -n chatwoot"),
        ("Pods", "kubectl get pods -n chatwoot | head -10"),
        ("Deployments", "kubectl get deployments -n chatwoot"),
    ]
    
    for name, cmd in checks:
        print(f"\n{name}:")
        code, out, err = run_ssh_command(f"export KUBECONFIG=/root/.kube/config && {cmd}", timeout=15)
        if out:
            print(out)
        else:
            print(f"  (vide ou erreur)")
    
    print()
    print("=" * 60)
    print("✅ Finalisation terminée")
    print(f"   Logs complets: {log_file}")
    print()
    
    return 0

if __name__ == "__main__":
    sys.exit(main())


