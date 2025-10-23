##################################################################
# Update-TomcatJDK.ps1 – JDK-Update für Tomcat (AST*)
########################bemb004##########################################

param(
    [Parameter(Mandatory = $true)]
    [string]$ComponentName,

    [string]$SenvFolder = "C:\DBA\nest\senv\local"
)

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

try {
    Write-Host "Delete service $ComponentName..."
    sc.exe delete $ComponentName | Out-Null
    Start-Sleep -Seconds 5
} catch { Write-Warning "Service could not be deleted: $($_.Exception.Message)" }

$cmd = @"
@echo off
set "SENV_HOME=C:\DBA\nest\senv"
call "%SENV_HOME%\senv_profile.cmd"
timeout /t 15 /nobreak >nul
call "%SENV_HOME%\senv.cmd" tomcat $ComponentName
timeout /t 15 /nobreak >nul
call C:\DBA\apache\JTC\$TomcatVersion\bin\service.bat install $ComponentName
timeout /t 15 /nobreak >nul
call startsrv
timeout /t 15 /nobreak >nul
exit
"@

$cmdPath = "C:\TEMP\reinstall_$ComponentName.cmd"
Set-Content -Path $cmdPath -Value $cmd -Encoding ASCII
Start-Process -FilePath "cmd.exe" -ArgumentList "/k `"$cmdPath`"" -WorkingDirectory "C:\DBA\nest\senv"

Write-Host "Restart component (wait 4 minutes)..." -ForegroundColor Yellow
Start-Sleep -Seconds 240

try {
    $svc = Get-Service -Name $ComponentName -ErrorAction Stop
    if ($svc.Status -eq 'Running') {
        Write-Host "'$ComponentName' runs with Tomcat $TomcatVersion and JDK $jdkVersion." -ForegroundColor Green
    } else {
        Write-Host "Service-Status: $($svc.Status)" -ForegroundColor Yellow
        exit 31
    }
} catch {
    Write-Host "Service '$ComponentName' not found." -ForegroundColor Red
    exit 32
}