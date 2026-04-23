$shell = New-Object -ComObject Shell.Application
$folder = $shell.Namespace('shell:AppsFolder')
$apps = $folder.Items() | Where-Object {$_.Name -like '*overlay*' -or $_.Name -like '*jarvis*' -or $_.Name -like '*Assistants*'}

$found = $false
foreach ($app in $apps) {
    Write-Host "Found: $($app.Name)"
    
    try {
        $shellPath = "shell:AppsFolder\$($app.Path)"
        Write-Host "Launching: $shellPath"
        
        # Use Start-Process with error handling
        $process = Start-Process $shellPath -PassThru -WindowStyle Hidden -ErrorAction Stop
        $found = $true
        break
    } catch {
        Write-Host "Error launching: $_"
    }
}

if (-not $found) {
    Write-Host "Warning: JARVIS Overlay not found in Start Menu"
}
