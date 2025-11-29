# suivi_installation_simple.ps1 - Suivi simple de l'installation
# Usage: .\suivi_installation_simple.ps1

$MODULES = @(
    @{Num=2; Name="Base OS & Sécurité"},
    @{Num=3; Name="PostgreSQL HA"},
    @{Num=4; Name="Redis HA"},
    @{Num=5; Name="RabbitMQ HA"},
    @{Num=6; Name="MinIO"},
    @{Num=7; Name="MariaDB Galera"},
    @{Num=8; Name="ProxySQL"},
    @{Num=9; Name="K3s HA"}
)

function Get-ModuleStatus {
    param($ModuleNum)
    
    $logFile = "/tmp/module${ModuleNum}_installation.log"
    $result = ssh install-01 "if [ -f $logFile ]; then if tail -10 $logFile | grep -qE '✅|succès|terminé|Module.*appliqué.*succès'; then echo 'COMPLETED'; elif tail -10 $logFile | grep -qE '❌|erreur|error|FAIL|Échec'; then echo 'ERROR'; else echo 'IN_PROGRESS'; fi; else echo 'PENDING'; fi" 2>$null
    
    return $result.Trim()
}

function Get-ModuleProgress {
    param($ModuleNum)
    
    $logFile = "/tmp/module${ModuleNum}_installation.log"
    $result = ssh install-01 "if [ -f $logFile ]; then tail -5 $logFile; else echo ''; fi" 2>$null
    
    return $result
}

# Calculer la progression
$completed = 0
$inProgress = 0
$currentModule = $null

foreach ($module in $MODULES) {
    $status = Get-ModuleStatus -ModuleNum $module.Num
    $module | Add-Member -NotePropertyName Status -NotePropertyValue $status -Force
    
    if ($status -eq "COMPLETED") {
        $completed++
    } elseif ($status -eq "IN_PROGRESS") {
        $inProgress++
        if (-not $currentModule) {
            $currentModule = $module
        }
    }
}

$totalModules = $MODULES.Count
$globalProgress = [math]::Round(($completed / $totalModules) * 100, 1)

# Affichage
Clear-Host
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  📊 SUIVI INSTALLATION KEYBUZZ" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

# Progression globale
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

# Module en cours
if ($currentModule) {
    Write-Host "🔄 MODULE EN COURS" -ForegroundColor Cyan
    Write-Host "   Module $($currentModule.Num) : $($currentModule.Name)" -ForegroundColor White
    Write-Host ""
    
    $progress = Get-ModuleProgress -ModuleNum $currentModule.Num
    if ($progress) {
        Write-Host "   Dernières activités :" -ForegroundColor Gray
        $progress -split "`n" | ForEach-Object {
            $line = $_.Trim()
            if ($line) {
                if ($line -match "✅|succès|terminé") {
                    Write-Host "   $line" -ForegroundColor Green
                } elseif ($line -match "❌|erreur|error|FAIL|Échec") {
                    Write-Host "   $line" -ForegroundColor Red
                } elseif ($line -match "INFO|INFO\]") {
                    Write-Host "   $line" -ForegroundColor Cyan
                } else {
                    Write-Host "   $line" -ForegroundColor Gray
                }
            }
        }
    }
    Write-Host ""
}

# État de tous les modules
Write-Host "📋 ÉTAT DES MODULES" -ForegroundColor Yellow
foreach ($module in $MODULES) {
    $statusIcon = switch ($module.Status) {
        "COMPLETED" { "✅" }
        "IN_PROGRESS" { "🔄" }
        "ERROR" { "❌" }
        default { "⏳" }
    }
    $statusColor = switch ($module.Status) {
        "COMPLETED" { "Green" }
        "IN_PROGRESS" { "Cyan" }
        "ERROR" { "Red" }
        default { "Gray" }
    }
    Write-Host "   $statusIcon Module $($module.Num) : $($module.Name)" -ForegroundColor $statusColor
}

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan

