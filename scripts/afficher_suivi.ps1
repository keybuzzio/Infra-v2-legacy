# afficher_suivi.ps1 - Affiche le suivi de l'installation

$MODULES = @(
    @{Num=2; Name="Base OS & Securite"},
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
    $result = ssh install-01 "if [ -f $logFile ]; then if tail -20 $logFile | grep -qE 'succes|termine|Module.*applique.*succes|CLUSTER.*OPERATIONNEL'; then echo 'COMPLETED'; elif tail -20 $logFile | grep -qE 'erreur|error|FAIL|Echec|annule'; then echo 'ERROR'; else echo 'IN_PROGRESS'; fi; else echo 'PENDING'; fi" 2>$null
    return $result.Trim()
}

$completed = 0
$inProgress = 0
$currentModule = $null

foreach ($module in $MODULES) {
    $status = Get-ModuleStatus -ModuleNum $module.Num
    $module | Add-Member -NotePropertyName Status -NotePropertyValue $status -Force
    if ($status -eq "COMPLETED") { $completed++ }
    elseif ($status -eq "IN_PROGRESS") { 
        $inProgress++
        if (-not $currentModule) { $currentModule = $module }
    }
}

$totalModules = $MODULES.Count
$globalProgress = [math]::Round(($completed / $totalModules) * 100, 1)

Clear-Host
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  SUIVI INSTALLATION KEYBUZZ - Modules 2 a 9" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "PROGRESSION GLOBALE" -ForegroundColor Yellow
Write-Host "   Modules termines : $completed / $totalModules" -ForegroundColor Green
Write-Host "   Modules en cours : $inProgress" -ForegroundColor Cyan
Write-Host "   Taux de completion : $globalProgress%" -ForegroundColor $(if ($globalProgress -eq 100) { "Green" } else { "Yellow" })
Write-Host ""

$barLength = 50
$filled = [math]::Round(($globalProgress / 100) * $barLength)
$bar = "█" * $filled + "░" * ($barLength - $filled)
Write-Host "   [$bar] $globalProgress%" -ForegroundColor $(if ($globalProgress -eq 100) { "Green" } else { "Yellow" })
Write-Host ""

if ($currentModule) {
    Write-Host "MODULE EN COURS" -ForegroundColor Cyan
    Write-Host "   Module $($currentModule.Num) : $($currentModule.Name)" -ForegroundColor White
    Write-Host ""
    $progress = ssh install-01 "tail -5 /tmp/module$($currentModule.Num)_installation.log 2>/dev/null" 2>$null
    if ($progress) {
        Write-Host "   Dernieres activites :" -ForegroundColor Gray
        $progress -split "`n" | ForEach-Object {
            $line = $_.Trim()
            if ($line) {
                if ($line -match "succes|termine|OK|OPERATIONNEL") {
                    Write-Host "   $line" -ForegroundColor Green
                } elseif ($line -match "erreur|error|FAIL|Echec|annule") {
                    Write-Host "   $line" -ForegroundColor Red
                } else {
                    Write-Host "   $line" -ForegroundColor Gray
                }
            }
        }
    }
    Write-Host ""
}

Write-Host "ETAT DES MODULES" -ForegroundColor Yellow
foreach ($module in $MODULES) {
    $statusIcon = switch ($module.Status) {
        "COMPLETED" { "OK" }
        "IN_PROGRESS" { "..." }
        "ERROR" { "ERR" }
        default { "..." }
    }
    $statusColor = switch ($module.Status) {
        "COMPLETED" { "Green" }
        "IN_PROGRESS" { "Cyan" }
        "ERROR" { "Red" }
        default { "Gray" }
    }
    Write-Host "   [$statusIcon] Module $($module.Num) : $($module.Name)" -ForegroundColor $statusColor
}

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan

