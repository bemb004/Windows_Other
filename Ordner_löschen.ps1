# Pfad zum Ordner oder zur Datei
$Path = "E:\DBA\nest\tomcat\ASTIHISA02"

# Besitz übernehmen
Write-Host "Übernehme Besitz..." -ForegroundColor Cyan
takeown /F $Path /R /D Y | Out-Null

# Volle Rechte für Administratoren setzen
Write-Host "Setze Berechtigungen..." -ForegroundColor Cyan
icacls $Path /grant Administrators:F /T | Out-Null

# Jetzt löschen
Write-Host "Lösche Ordner..." -ForegroundColor Cyan
Remove-Item -Path $Path -Recurse -Force

Write-Host "✅ Ordner wurde erfolgreich gelöscht!" -ForegroundColor Green