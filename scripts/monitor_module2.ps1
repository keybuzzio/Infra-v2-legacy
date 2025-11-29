# Script PowerShell pour surveiller le Module 2
# Usage: .\monitor_module2.ps1 [--interval SECONDS]

param(
    [int]$Interval = 30
)

$SSH_KEY = "..\..\SSH\keybuzz_infra"
$HOST = "root@91.98.128.153"
$LOG_FILE = "/tmp/module2_final_complet.log"
$TOTAL_SERVERS = 49

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " [KeyBuzz] Surveillance Module 2" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Surveillance en cours... (Ctrl+C pour arrêter)" -ForegroundColor Yellow
Write-Host "Intervalle: $Interval secondes" -ForegroundColor Gray
Write-Host ""

$previousCount = 0
$completed = $false

while (-not $completed) {
    try {
        $result = plink.exe -ssh -i $SSH_KEY -batch $HOST @"
cd /opt/keybuzz-installer && if [ -f $LOG_FILE ]; then success=\$(grep -c 'Serveur.*traite avec succes' $LOG_FILE 2>/dev/null || echo 0); errors=\$(grep -c 'Erreur' $LOG_FILE 2>/dev/null || echo 0); running=\$(ps aux | grep -q '[a]pply_base_os_to_all' && echo 'true' || echo 'false'); echo "\$success|\$errors|\$running"; else echo "0|0|false"; fi
"@

        if ($result) {
            $parts = $result -split '\|'
            $successCount = [int]$parts[0]
            $errorCount = [int]$parts[1]
            $isRunning = $parts[2] -eq 'true'
            
            $timestamp = Get-Date -Format "HH:mm:ss"
            $remaining = $TOTAL_SERVERS - $successCount
            $percentage = [math]::Round(($successCount / $TOTAL_SERVERS) * 100, 1)
            
            Clear-Host
            Write-Host "============================================================" -ForegroundColor Cyan
            Write-Host " [KeyBuzz] Surveillance Module 2" -ForegroundColor Cyan
            Write-Host "============================================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Dernière vérification: $timestamp" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Progression:" -ForegroundColor White
            Write-Host "  Serveurs traités: $successCount/$TOTAL_SERVERS ($percentage%)" -ForegroundColor Green
            Write-Host "  Erreurs: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Green" })
            Write-Host "  Restants: $remaining" -ForegroundColor Yellow
            Write-Host ""
            
            if ($isRunning) {
                Write-Host "Status: " -NoNewline
                Write-Host "EN COURS" -ForegroundColor Green
                
                if ($successCount -gt $previousCount) {
                    Write-Host ""
                    Write-Host "✅ Nouveau serveur traité ! (+$($successCount - $previousCount))" -ForegroundColor Green
                }
            } else {
                Write-Host "Status: " -NoNewline
                Write-Host "TERMINÉ" -ForegroundColor Yellow
                Write-Host ""
                
                if ($successCount -eq $TOTAL_SERVERS) {
                    Write-Host "============================================================" -ForegroundColor Green
                    Write-Host " ✅ TOUS LES SERVEURS ONT ÉTÉ TRAITÉS AVEC SUCCÈS !" -ForegroundColor Green
                    Write-Host "============================================================" -ForegroundColor Green
                    Write-Host ""
                    Write-Host "Le Module 2 est terminé. Vous pouvez passer aux modules suivants." -ForegroundColor White
                    $completed = $true
                } else {
                    Write-Host "⚠️  Installation terminée mais certains serveurs n'ont pas été traités" -ForegroundColor Yellow
                    Write-Host "   Vérifiez les logs pour plus de détails." -ForegroundColor Yellow
                    $completed = $true
                }
            }
            
            $previousCount = $successCount
        }
        
        if (-not $completed) {
            Start-Sleep -Seconds $Interval
        }
    } catch {
        Write-Host "Erreur lors de la vérification: $_" -ForegroundColor Red
        Start-Sleep -Seconds $Interval
    }
}

Write-Host ""
Write-Host "Surveillance terminée." -ForegroundColor Gray


