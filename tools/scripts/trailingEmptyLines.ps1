# Remove-TrailingEmptyLines.ps1
# Removes trailing blank lines at the end of each file in the current directory

$files = Get-ChildItem -Path . -File -Recurse | Where-Object {
    $content = Get-Content -Path $_.FullName -Raw
    $content -and $content -ne $content.TrimEnd()
}

if (-not $files) {
    Write-Host "No files to process." -ForegroundColor Cyan
    exit
}

foreach ($file in $files) {
    try {
        $content = Get-Content -Path $file.FullName -Raw
        $trimmed = $content.TrimEnd()
        Set-Content -Path $file.FullName -Value $trimmed -NoNewline
        Write-Host "Processed: $($file.FullName)" -ForegroundColor Green
    }
    catch {
        Write-Host "Error on $($file.FullName): $_" -ForegroundColor Red
    }
}

Write-Host "`nDone." -ForegroundColor Cyan