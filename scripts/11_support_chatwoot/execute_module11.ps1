# Script PowerShell pour exécuter la finalisation du Module 11

$SSH_KEY = "$env:USERPROFILE\.ssh\keybuzz_auto"
$HOST = "root@91.98.128.153"
$SCRIPT_PATH = "/opt/keybuzz-installer-v2/scripts/11_support_chatwoot/run_with_status.sh"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " [KeyBuzz] Module 11 - Finalisation" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Étape 1 : Transférer le script
Write-Host "1. Transfert du script..." -ForegroundColor Yellow
$scriptContent = Get-Content "Infra\scripts\11_support_chatwoot\run_with_status.sh" -Raw -Encoding UTF8
$scriptContent | ssh -i $SSH_KEY $HOST "cat > /tmp/run_with_status.sh && chmod +x /tmp/run_with_status.sh && echo 'OK'"

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Erreur lors du transfert" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Script transféré" -ForegroundColor Green
Write-Host ""

# Étape 2 : Lancer le script en arrière-plan
Write-Host "2. Lancement du script..." -ForegroundColor Yellow
$pid = ssh -i $SSH_KEY $HOST "nohup bash /tmp/run_with_status.sh > /dev/null 2>&1 & echo `$!"
Write-Host "✅ Script lancé (PID: $pid)" -ForegroundColor Green
Write-Host ""

# Étape 3 : Suivre le statut
Write-Host "3. Suivi de l'exécution..." -ForegroundColor Yellow
Write-Host "   (Appuyez sur Ctrl+C pour arrêter le suivi)" -ForegroundColor Gray
Write-Host ""

$maxWait = 1200  # 20 minutes
$startTime = Get-Date
$lastLine = 0

try {
    while ((Get-Date) - $startTime -lt [TimeSpan]::FromSeconds($maxWait)) {
        $status = ssh -i $SSH_KEY $HOST "tail -n +$lastLine /tmp/module11_status.txt 2>/dev/null || echo ''"
        
        if ($status) {
            $lines = $status -split "`n"
            foreach ($line in $lines) {
                if ($line.Trim()) {
                    Write-Host $line
                    $lastLine++
                }
            }
        }
        
        # Vérifier si le processus est toujours en cours
        $running = ssh -i $SSH_KEY $HOST "ps -p $pid > /dev/null 2>&1 && echo 'RUNNING' || echo 'DONE'"
        if ($running -eq "DONE") {
            Write-Host ""
            Write-Host "✅ Script terminé" -ForegroundColor Green
            break
        }
        
        Start-Sleep -Seconds 10
    }
} catch {
    Write-Host ""
    Write-Host "⚠️ Suivi interrompu" -ForegroundColor Yellow
    Write-Host "   Le script continue d'exécution sur le serveur" -ForegroundColor Gray
}

# Étape 4 : Afficher le statut final
Write-Host ""
Write-Host "4. Statut final:" -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Cyan
ssh -i $SSH_KEY $HOST "cat /tmp/module11_status.txt 2>/dev/null || echo 'Fichier de statut non trouvé'"
Write-Host ""

# Étape 5 : Vérifier l'état Kubernetes
Write-Host "5. État Kubernetes:" -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Cyan
ssh -i $SSH_KEY $HOST "export KUBECONFIG=/root/.kube/config && kubectl get pods -n chatwoot 2>&1 | head -10"
Write-Host ""
ssh -i $SSH_KEY $HOST "export KUBECONFIG=/root/.kube/config && kubectl get deployments -n chatwoot 2>&1"
Write-Host ""

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "✅ Finalisation terminée" -ForegroundColor Green
Write-Host "   Logs: /tmp/module11_finalisation.log" -ForegroundColor Gray
Write-Host "   Rapports: /opt/keybuzz-installer-v2/reports/" -ForegroundColor Gray
Write-Host "==============================================================" -ForegroundColor Cyan


