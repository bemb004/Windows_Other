function Create-SenvShortcut {
    $desktop = [System.Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop "SEnv-Shortcut.lnk"
    $targetPath = "$env:SystemRoot\system32\cmd.exe"
    $arguments = '/K "C:\DBA\nest\senv\senv_profile.cmd & C:\DBA\nest\senv\senv.cmd"'

    if (-not (Test-Path $shortcutPath)) {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $targetPath
        $shortcut.Arguments = $arguments
        $shortcut.Save()
        Write-Host "SEnv-Shortcut wurde auf dem Desktop erstellt."
    } else {
        Write-Host "SEnv-Shortcut existiert bereits auf dem Desktop."
    }
}

# Shortcut erstellen
Create-SenvShortcut