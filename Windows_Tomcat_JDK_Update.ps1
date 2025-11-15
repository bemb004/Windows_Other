##################################################################
# Update-TomcatJDK.ps1 JDK-Update für Tomcat (AST*)
########################bemb004##########################################

param(
    [Parameter(Mandatory = $true)]
    [string]$ComponentName,

    [string]$SenvFolder = "C:\DBA\nest\senv\local"
)
#########################TEMP_Ordner#########################################
function Ensure-TempFolder {
    param(
        [string]$Path = "C:\TEMP"
    )

    try {
        if (-not (Test-Path -Path $Path)) {
            Write-Host "Folder '$Path' not found — creating..." -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Host "Folder '$Path' created successfully." -ForegroundColor Green
        }
        else {
            Write-Host "Folder '$Path' already exists." -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "VERROR: Could not verify or create '$Path' — $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ((Get-Date -Format s) + " - VRETURNCODE : 11")
        exit 11
    }
}
Ensure-TempFolder -Path "C:\TEMP"
########################Backup_componententyp.senv##########################################
$resolvedType = "tomcat"
function Backup-ComponentTypSenv {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComponentType = "tomcat",
        [string]$SenvFolder = "C:\DBA\nest\senv\local"
    )

    try {
        $senvFile = Join-Path $SenvFolder "$ComponentType.senv"
        if (-not (Test-Path $senvFile)) {
            Write-Host "No $ComponentType.senv found at $SenvFolder, skipping backup." -ForegroundColor Yellow
            return
        }

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupFile = "$senvFile.$timestamp.bak"

        Copy-Item -Path $senvFile -Destination $backupFile -Force

        Write-Host "Backup created: $backupFile" -ForegroundColor Green
        Write-Host ((Get-Date -Format s) + " - INFO  : $ComponentType.senv backup stored at $backupFile")
    }
    catch {
        Write-Host "VERROR: Could not back up $ComponentType.senv — $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ((Get-Date -Format s) + " - VRETURNCODE : 12")
        exit 12
    }
}
Backup-ComponentTypSenv -ComponentType $resolvedType

###########################mondisable#######################################
$cmd = @"
@echo off
set "SENV_HOME=C:\DBA\nest\senv"
call "%SENV_HOME%\senv_profile.cmd"
timeout /t 10 /nobreak >nul
call "%SENV_HOME%\senv.cmd" tomcat $ComponentName
timeout /t 10 /nobreak >nul
call mondisable
timeout /t 10 /nobreak >nul
exit
"@

$cmdPath = "C:\TEMP\jdkupdate_$ComponentName.cmd"
Set-Content -Path $cmdPath -Value $cmd -Encoding ASCII
Start-Process -FilePath "cmd.exe" -ArgumentList "/k `"$cmdPath`"" -WorkingDirectory "C:\DBA\nest\senv"



Write-Host "wait component (wait 1 minutes)..." -ForegroundColor Yellow
Start-Sleep -Seconds 60
###############################stoppen_Service###################################
try {
    $svc = Get-Service -Name $ComponentName -ErrorAction Stop
    if ($svc.Status -eq 'Stopped') {
        Write-Host "Service $ComponentName is already stopped." -ForegroundColor Yellow
    }
    else {
        Write-Host "Stoppe Service $ComponentName..."
        Stop-Service -Name $ComponentName -Force -ErrorAction Stop
        Start-Sleep -Seconds 5
        Write-Host "Service $ComponentName was stopped." -ForegroundColor Yellow
    }
}
catch {
    Write-Warning "Service $ComponentName was not found: $($_.Exception.Message)"
}

######################tomcat.senv############################################
function Find-TomcatBlock {
    param(
        [string]$ComponentName,
        [string]$SenvFolder
    )
    $file = Join-Path $SenvFolder "tomcat.senv"
    if (-not (Test-Path $file)) { throw "tomcat.senv not found: $file" }

    $lines = Get-Content -Path $file -Encoding UTF8
    $start = ($lines | ForEach-Object { $_.Trim() }).IndexOf("[$ComponentName]")
    if ($start -lt 0) { throw "block [$ComponentName] not found in $file." }

    $end = $start + 1
    while ($end -lt $lines.Count -and $lines[$end] -notmatch '^\s*\[.+\]\s*$') { $end++ }

    [pscustomobject]@{
        File  = $file
        Lines = $lines
        Start = $start
        End   = $end
        Block = $lines[($start + 1)..($end - 1)]
    }
}
##################################################################
function Update-JavaHomeInBlock {
    param(
        [string[]]$Block,
        [string]$NewJdkPath
    )
    $found = $false
    for ($i=0; $i -lt $Block.Count; $i++) {
        if ($Block[$i] -match '^\s*SET\s+set\s+JAVA_HOME=') {
            $Block[$i] = "SET set JAVA_HOME=$NewJdkPath"
            $found = $true
        }
    }
    if (-not $found) { $Block += "SET set JAVA_HOME=$NewJdkPath" }
    return ,$Block
}
##################################################################
function Write-BlockBack {
    param(
        [string[]]$AllLines,
        [int]$Start,
        [int]$End,
        [string[]]$NewBlock,
        [string]$FilePath
    )
    $out = @()
    if ($Start -gt 0) { $out += $AllLines[0..$Start] } else { $out += $AllLines[0] }
    $out += $NewBlock
    if ($End -lt $AllLines.Count) { $out += $AllLines[$End..($AllLines.Count-1)] }
    Set-Content -Path $FilePath -Value $out -Encoding UTF8
}
##################################################################
function Get-TomcatVersionFromBlock {
    param([string[]]$Block)
    $cat = $Block | Where-Object { $_ -match '^\s*SET\s+set\s+CATALINA_HOME\s*=' } | Select-Object -First 1
    if (-not $cat) { throw "CATALINA_HOME not found in block." }
    if ($cat -match '\\JTC\\(?<ver>[^\\\s]+)') {
        return $Matches['ver']
    }
    throw "Tomcat version could not be extracted from CATALINA_HOME: $cat"
}

if ($ComponentName -notmatch '^AST') {
    Write-Host "This script is only for Tomcat components (AST*)." -ForegroundColor Red
    exit 8
}

$jdkVersion = Read-Host "New JDK version"
$jdkCandidates = @("C:\DBA\adopt-openjdk\$jdkVersion","C:\DBA\java\$jdkVersion")
$jdkPath = $jdkCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $jdkPath) {
    Write-Host "No JDK directory found:" -ForegroundColor Red
    $jdkCandidates | ForEach-Object { Write-Host "  $_" }
    exit 11
}
Write-Host "New JDK: $jdkPath" -ForegroundColor Green

$blk = Find-TomcatBlock -ComponentName $ComponentName -SenvFolder $SenvFolder

$newBlock = Update-JavaHomeInBlock -Block $blk.Block -NewJdkPath $jdkPath
Write-BlockBack -AllLines $blk.Lines -Start $blk.Start -End $blk.End -NewBlock $newBlock -FilePath $blk.File
Write-Host "JAVA_HOME updated in tomcat.senv → $jdkPath" -ForegroundColor Green

$TomcatVersion = Get-TomcatVersionFromBlock -Block $newBlock
Write-Host "Tomcat version from CATALINA_HOME: $TomcatVersion" -ForegroundColor Cyan

#################################################
function Update-JvmRegistryPath {
    param(
        [string]$ServiceName,
        [string]$JdkPath
    )

    $newJvm = Join-Path $JdkPath "bin\server\jvm.dll"

    if (-not (Test-Path $newJvm)) {
        Write-Host "ERROR: JVM file not found at $newJvm" -ForegroundColor Red
        exit 13
    }

    $regPaths = @(
        "HKLM:\SOFTWARE\Apache Software Foundation\Procrun 2.0\$ServiceName\Parameters\Java",
        "HKLM:\SOFTWARE\WOW6432Node\Apache Software Foundation\Procrun 2.0\$ServiceName\Parameters\Java"
    )

    foreach ($path in $regPaths) {
        if (Test-Path $path) {
            try {
                Set-ItemProperty -Path $path -Name "Jvm" -Value $newJvm -ErrorAction Stop
                Write-Host "Updated JVM registry path in:`n$path" -ForegroundColor Green
                return
            }
            catch {
                Write-Host "ERROR: Could not write new JVM path to $path — $($_.Exception.Message)" -ForegroundColor Red
                exit 14
            }
        }
    }

    Write-Host "WARNING: No Procrun Java registry path found for service '$ServiceName'." -ForegroundColor Yellow
}
Update-JvmRegistryPath -ServiceName $ComponentName -JdkPath $jdkPath
#################################################

#################monenble#################################################
$cmd = @"
@echo off
set "SENV_HOME=C:\DBA\nest\senv"
call "%SENV_HOME%\senv_profile.cmd"
timeout /t 10 /nobreak >nul
call "%SENV_HOME%\senv.cmd" tomcat $ComponentName
timeout /t 10 /nobreak >nul
call monenable
timeout /t 10 /nobreak >nul
exit
"@

$cmdPath = "C:\TEMP\jdkupdate_$ComponentName.cmd"
Set-Content -Path $cmdPath -Value $cmd -Encoding ASCII
Start-Process -FilePath "cmd.exe" -ArgumentList "/k `"$cmdPath`"" -WorkingDirectory "C:\DBA\nest\senv"

##################################################################

Write-Host "Restart component (wait 1 minutes)..." -ForegroundColor Yellow
Start-Sleep -Seconds 60

$service = Get-Service -Name $ComponentName -ErrorAction SilentlyContinue
$success = $false
$currentVersion = $null

if ($service) {
    if ($service.Status -ne 'Running') {
        Write-Host "Service '$ComponentName' is not running (Status: $($service.Status)). Attempting to start..." -ForegroundColor Yellow
        try {
            Start-Service -Name $ComponentName -ErrorAction Stop
            Start-Sleep -Seconds 5
            $service.Refresh()
            if ($service.Status -eq 'Running') {
                Write-Host "Service '$ComponentName' started successfully with Tomcat $TomcatVersion and JDK $jdkVersion." -ForegroundColor Green
                $success = $true
            }
            else {
                Write-Host "Service '$ComponentName' could not be started. Current status: $($service.Status)" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "VERROR: Failed to start service '$ComponentName' — $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ((Get-Date -Format s) + " - VRETURNCODE : 31")
        }
    }
    else {
        Write-Host "Service '$ComponentName' is already running — no action needed." -ForegroundColor Gray
    }

    if ($success) {
    Write-Host "`nComponent '$ComponentName' runs successfully with $TomcatVersion and new JDK $jdkVersion.." -ForegroundColor Green
}
else {
    Write-Host "`nUpdate of '$ComponentName' unsuccessful:" -ForegroundColor Red
 }
}
##################################################################
#tomcat.senv to UTF-8
$TomcatSenvPath = "C:\DBA\nest\senv\local\tomcat.senv"
if (Test-Path $TomcatSenvPath) {
    Write-Host "Converting tomcat.senv to UTF-8 (no BOM)..." -ForegroundColor Yellow

    $content = [System.IO.File]::ReadAllText($TomcatSenvPath)

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText($TomcatSenvPath, $content, $utf8NoBom)

    Write-Host "tomcat.senv converted to UTF-8 (no BOM)." -ForegroundColor Green
}