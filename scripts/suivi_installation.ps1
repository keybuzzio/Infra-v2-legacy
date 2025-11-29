# suivi_installation.ps1 - Suivi de l'installation des modules KeyBuzz
# Affiche le taux de complétion global et du module en cours

param(
    [Parameter(Mandatory=$false)]
    [int]$RefreshInterval = 10  # Secondes entre chaque rafraîchissement
)

$MODULES = @(
    @{Num=2; Name="Base OS & Sécurité"; Script="apply_base_os_to_all.sh"; Status="pending"},
    @{Num=3; Name="PostgreSQL HA"; Script="03_pg_apply_all.sh"; Status="pending"},
    @{Num=4; Name="Redis HA"; Script="04_redis_apply_all.sh"; Status="pending"},
    @{Num=5; Name="RabbitMQ HA"; Script="05_rmq_apply_all.sh"; Status="pending"},
    @{Num=6; Name="MinIO"; Script="06_minio_apply_all.sh"; Status="pending"},
    @{Num=7; Name="MariaDB Galera"; Script="07_maria_apply_all.sh"; Status="pending"},
    @{Num=8; Name="ProxySQL"; Script="08_proxysql_apply_all.sh"; Status="pending"},
    @{Num=9; Name="K3s HA"; Script="09_k3s_apply_all.sh"; Status="pending"}
)

function Get-ModuleStatus {
    param($ModuleNum)
    
    $logFile = "/tmp/module${ModuleNum}_installation.log"
    $result = ssh install-01 "if [ -f $logFile ]; then tail -5 $logFile | grep -E '(✅|❌|terminé|succès|erreur|error)' | tail -1 || echo 'EN_COURS'; else echo 'PAS_DEMARRE'; fi" 2>$null
    
    if ($result -match "✅|succès|terminé") {
        return "completed"
    } elseif ($result -match "❌|erreur|error|FAIL") {
        return "error"
    } elseif ($result -match "EN_COURS") {
        return "in_progress"
    } else {
        return "pending"
    }
}

function Get-CurrentModuleProgress {
    param($ModuleNum)
    
    $logFile = "/tmp/module${ModuleNum}_installation.log"
    $result = ssh install-01 "if [ -f $logFile ]; then wc -l < $logFile; else echo '0'; fi" 2>$null
    
    # Estimation basée sur le nombre de lignes (approximatif)
    $lines = [int]$result
    if ($lines -lt 10) { return 5 }
    if ($lines -lt 50) { return 15 }
    if ($lines -lt 100) { return 30 }
    if ($lines -lt 200) { return 50 }
    if ($lines -lt 300) { return 70 }
    if ($lines -lt 400) { return 85 }
    return 95
}

function Show-Progress {
    Clear-Host
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  📊 SUIVI INSTALLATION KEYBUZZ - Modules 2 à 9" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Calculer le taux de complétion global
    $completed = 0
    $inProgress = 0
    $currentModule = $null
    
    foreach ($module in $MODULES) {
        $status = Get-ModuleStatus -ModuleNum $module.Num
        $module.Status = $status
        
        if ($status -eq "completed") {
            $completed++
        } elseif ($status -eq "in_progress") {
            $inProgress++
            if (-not $currentModule) {
                $currentModule = $module
            }
        }
    }
    
    $totalModules = $MODULES.Count
    $globalProgress = [math]::Round(($completed / $totalModules) * 100, 1)
    
    # Afficher la progression globale
    Write-Host "📈 PROGRESSION GLOBALE" -ForegroundColor Yellow
    Write-Host "   Modules terminés : $completed / $totalModules" -ForegroundColor Green
    Write-Host "   Modules en cours : $inProgress" -ForegroundColor Cyan
    Write-Host "   Taux de complétion : $globalProgress%" -ForegroundColor $(if ($globalProgress -eq 100) { "Green" } else { "Yellow" })
    Write-Host ""
    
    # Barre de progression globale
    $barLength = 50
    $filled = [math]::Round(($globalProgress / 100) * $barLength)
    $bar = "█" * $filled + "░" * ($barLength - $filled)
    Write-Host "   [$bar] $globalProgress%" -ForegroundColor $(if ($globalProgress -eq 100) { "Green" } else { "Yellow" })
    Write-Host ""
    
    # Afficher le module en cours
    if ($currentModule) {
        Write-Host "🔄 MODULE EN COURS" -ForegroundColor Cyan
        Write-Host "   Module $($currentModule.Num) : $($currentModule.Name)" -ForegroundColor White
        $moduleProgress = Get-CurrentModuleProgress -ModuleNum $currentModule.Num
        Write-Host "   Progression estimée : $moduleProgress%" -ForegroundColor Yellow
        Write-Host ""
        
        # Barre de progression du module
        $moduleBarLength = 50
        $moduleFilled = [math]::Round(($moduleProgress / 100) * $moduleBarLength)
        $moduleBar = "█" * $moduleFilled + "░" * ($moduleBarLength - $moduleFilled)
        Write-Host "   [$moduleBar] $moduleProgress%" -ForegroundColor Yellow
        Write-Host ""
        
        # Dernières lignes du log
        Write-Host "📝 DERNIÈRES ACTIVITÉS" -ForegroundColor Cyan
        $lastLines = ssh install-01 "tail -3 /tmp/module$($currentModule.Num)_installation.log 2>/dev/null | head -3" 2>$null
        if ($lastLines) {
            $lastLines -split "`n" | ForEach-Object {
                if ($_ -match "✅|succès") {
                    Write-Host "   $_" -ForegroundColor Green
                } elseif ($_ -match "❌|erreur|error") {
                    Write-Host "   $_" -ForegroundColor Red
                } else {
                    Write-Host "   $_" -ForegroundColor Gray
                }
            }
        }
        Write-Host ""
    }
    
    # État de tous les modules
    Write-Host "📋 ÉTAT DES MODULES" -ForegroundColor Yellow
    foreach ($module in $MODULES) {
        $statusIcon = switch ($module.Status) {
            "completed" { "✅" }
            "in_progress" { "🔄" }
            "error" { "❌" }
            default { "⏳" }
        }
        $statusColor = switch ($module.Status) {
            "completed" { "Green" }
            "in_progress" { "Cyan" }
            "error" { "Red" }
            default { "Gray" }
        }
        Write-Host "   $statusIcon Module $($module.Num) : $($module.Name)" -ForegroundColor $statusColor
    }
    
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "   Appuyez sur Ctrl+C pour arrêter le suivi" -ForegroundColor Gray
    Write-Host "   Rafraîchissement automatique toutes les $RefreshInterval secondes" -ForegroundColor Gray
    Write-Host "==============================================================" -ForegroundColor Cyan
}

# Boucle principale
try {
    while ($true) {
        Show-Progress
        Start-Sleep -Seconds $RefreshInterval
    }
} catch {
    Write-Host "`nArrêt du suivi." -ForegroundColor Yellow
}

