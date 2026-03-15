# generate-docinfo.ps1

$docinfoPath = "docinfo.html"
$assetsPath  = "assets"

# vérifier la présence de docinfo.html
if (-not (Test-Path $docinfoPath)) {
    Write-Host "docinfo.html absent, arrêt."
    exit
}

# vérifier la présence du dossier assets
if (-not (Test-Path $assetsPath)) {
    Write-Host "Dossier assets absent, arrêt."
    exit
}

# récupérer les fichiers CSS et JS
$cssFiles = Get-ChildItem -Path $assetsPath -Filter "*.css" -Recurse
$jsFiles  = Get-ChildItem -Path $assetsPath -Filter "*.js"  -Recurse

# s'il n'y a aucun asset, arrêt sans toucher au fichier
if ($cssFiles.Count -eq 0 -and $jsFiles.Count -eq 0) {
    Write-Host "Aucun asset trouvé, arrêt."
    exit
}

# réécriture complète de docinfo.html
$output = ""

foreach ($file in $cssFiles) {
    $css     = Get-Content $file.FullName -Raw -Encoding UTF8
    $output += "<style>`n$css`n</style>`n"
}

foreach ($file in $jsFiles) {
    $js      = Get-Content $file.FullName -Raw -Encoding UTF8
    $output += "<script>`n$js`n</script>`n"
}

$output | Set-Content $docinfoPath -Encoding UTF8
Write-Host "docinfo.html réécrit avec succès ($($cssFiles.Count) CSS, $($jsFiles.Count) JS)."