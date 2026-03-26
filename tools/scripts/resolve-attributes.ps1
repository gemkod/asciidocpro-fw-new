<#
.SYNOPSIS
    Résout tous les attributs AsciiDoc du framework AsciidocPro en suivant
    récursivement les inclusions à partir du fichier loader.

.DESCRIPTION
    Ce script parcourt fw/system/loader.adoc, suit les directives include::
    de façon récursive, collecte toutes les déclarations d'attributs, résout
    les références {attribut} dans les valeurs, et génère :
    - fw/_dump/attributes-dump.adoc (fichier courant, utilisé par l'application)
    - fw/_dump/attributes-dump_v{N}.adoc (copie versionnée archivée)

    Le numéro de version est auto-incrémenté. Le script demande une note
    de version à chaque exécution.

.PARAMETER Backend
    Le backend cible pour résoudre les directives ifdef::backend-*.
    Valeurs possibles : pdf, html5. Par défaut : pdf.

.PARAMETER ShowUnresolved
    Affiche les attributs dont la valeur contient encore des références
    non résolues {xxx}.

.EXAMPLE
    .\resolve-attributes.ps1
    .\resolve-attributes.ps1 -Backend html5
    .\resolve-attributes.ps1 -ShowUnresolved
#>

param(
    [ValidateSet("pdf", "html5")]
    [string]$Backend = "pdf",

    [switch]$ShowUnresolved
)

$ErrorActionPreference = "Stop"

# --- Chemins ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Resolve-Path (Join-Path (Join-Path $scriptDir "..") "..")).Path
$fwRoot = Join-Path $projectRoot "fw"
$loaderFile = Join-Path (Join-Path $fwRoot "system") "loader.adoc"
$dumpDir = Join-Path $fwRoot "_dump"
$versionFile = Join-Path $dumpDir ".version"
$hashFile = Join-Path $dumpDir ".hash"
$dumpFile = Join-Path $dumpDir "attributes-dump.adoc"

if (-not (Test-Path $loaderFile)) {
    Write-Error "Fichier loader introuvable : $loaderFile"
    exit 1
}

# Créer le dossier _dump s'il n'existe pas
if (-not (Test-Path $dumpDir)) {
    New-Item -ItemType Directory -Path $dumpDir -Force | Out-Null
    Write-Host "Dossier cree : $dumpDir" -ForegroundColor DarkGray
}

# --- Lire la version courante ---
if (Test-Path $versionFile) {
    $lastVersion = [int](Get-Content $versionFile -Raw).Trim()
}
else {
    $lastVersion = 0
}
if (Test-Path $hashFile) {
    $lastHash = (Get-Content $hashFile -Raw).Trim()
}
else {
    $lastHash = ""
}

# --- Dictionnaire des attributs ---
$attributes = [ordered]@{}
$attributeSources = [ordered]@{}  # attribut -> fichier source
$attributeLog = [System.Collections.ArrayList]::new()
$visitedFiles = [System.Collections.Generic.HashSet[string]]::new()

$script:depth = 0
$script:maxDepth = 20

function Resolve-AttributeValue {
    param([string]$Value)

    $maxPasses = 10
    $pass = 0
    $result = $Value

    while ($pass -lt $maxPasses -and $result -match '\{[a-zA-Z0-9_-]+\}') {
        $newResult = $result
        $newResult = [regex]::Replace($newResult, '\{([a-zA-Z0-9_-]+)\}', {
            param($match)
            $attrName = $match.Groups[1].Value
            if ($attributes.Contains($attrName)) {
                return $attributes[$attrName]
            }
            else {
                return $match.Value
            }
        })

        if ($newResult -eq $result) { break }
        $result = $newResult
        $pass++
    }

    return $result
}

function Evaluate-Condition {
    param([string]$Condition)

    $resolved = Resolve-AttributeValue $Condition

    if ($resolved -match '^\s*"(.*)"\s*(==|!=)\s*"(.*)"\s*$') {
        $left = $Matches[1]
        $op = $Matches[2]
        $right = $Matches[3]

        if ($op -eq "==") { return $left -eq $right }
        if ($op -eq "!=") { return $left -ne $right }
    }

    if ($resolved -match '^\s*(\S+)\s*(==|!=)\s*(\S+)\s*$') {
        $left = $Matches[1]
        $op = $Matches[2]
        $right = $Matches[3]

        if ($op -eq "==") { return $left -eq $right }
        if ($op -eq "!=") { return $left -ne $right }
    }

    Write-Warning "Condition ifeval non evaluable: $Condition (resolue: $resolved)"
    return $true
}

function Process-AdocFile {
    param(
        [string]$FilePath,
        [string]$BaseDir
    )

    $script:depth++
    if ($script:depth -gt $script:maxDepth) {
        Write-Warning "Profondeur maximale d'inclusion atteinte ($($script:maxDepth)) pour : $FilePath"
        $script:depth--
        return
    }

    $normalizedPath = [System.IO.Path]::GetFullPath($FilePath)

    if (-not $visitedFiles.Add($normalizedPath)) {
        Write-Warning "Inclusion circulaire detectee, fichier ignore : $normalizedPath"
        $script:depth--
        return
    }

    if (-not (Test-Path $normalizedPath)) {
        Write-Warning "Fichier non trouve : $normalizedPath"
        $script:depth--
        $visitedFiles.Remove($normalizedPath) | Out-Null
        return
    }

    $indent = "  " * $script:depth
    Write-Host "${indent}> Traitement: $normalizedPath" -ForegroundColor Cyan

    $lines = Get-Content -Path $normalizedPath -Encoding UTF8
    $currentDir = Split-Path -Parent $normalizedPath

    $conditionStack = [System.Collections.Stack]::new()
    $inBlockComment = $false

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        # Blocs de commentaires ////
        if ($trimmed -eq '////') {
            $inBlockComment = -not $inBlockComment
            continue
        }
        if ($inBlockComment) { continue }

        # Commentaires simples
        if ($trimmed.StartsWith('//')) { continue }

        # Vérifier si on est dans un bloc conditionnel inactif
        $isActive = $true
        foreach ($cond in $conditionStack) {
            if (-not $cond.Active) {
                $isActive = $false
                break
            }
        }

        # --- Directives conditionnelles ---

        # ifdef::backend-xxx[]
        if ($trimmed -match '^ifdef::backend-(\S+?)\[\]$') {
            $targetBackend = $Matches[1]
            $conditionStack.Push(@{
                Type   = "ifdef"
                Active = ($targetBackend -eq $Backend)
            })
            continue
        }

        # ifdef::attribut[]
        if ($trimmed -match '^ifdef::([a-zA-Z0-9_-]+)\[\]$') {
            $attrName = $Matches[1]
            $conditionStack.Push(@{
                Type   = "ifdef"
                Active = $attributes.Contains($attrName)
            })
            continue
        }

        # ifndef::attribut[]
        if ($trimmed -match '^ifndef::([a-zA-Z0-9_-]+)\[\]$') {
            $attrName = $Matches[1]
            $conditionStack.Push(@{
                Type   = "ifdef"
                Active = (-not $attributes.Contains($attrName))
            })
            continue
        }

        # ifeval::[condition]
        if ($trimmed -match '^ifeval::\[(.+)\]$') {
            $condition = $Matches[1]
            if ($isActive) {
                $evalResult = Evaluate-Condition $condition
                $conditionStack.Push(@{
                    Type   = "ifeval"
                    Active = $evalResult
                })
            }
            else {
                $conditionStack.Push(@{
                    Type   = "ifeval"
                    Active = $false
                })
            }
            continue
        }

        # endif::
        if ($trimmed -match '^endif::') {
            if ($conditionStack.Count -gt 0) {
                $conditionStack.Pop() | Out-Null
            }
            continue
        }

        # Si bloc inactif, on skip
        if (-not $isActive) { continue }

        # --- Déclarations d'attributs ---

        # :attribut!: (suppression)
        if ($trimmed -match '^:([a-zA-Z0-9_-]+)!:\s*$') {
            $attrName = $Matches[1]
            if ($attributes.Contains($attrName)) {
                $attributes.Remove($attrName)
                $attributeSources.Remove($attrName)
                [void]$attributeLog.Add(@{
                    Name   = $attrName
                    Action = "UNSET"
                    File   = $normalizedPath
                })
            }
            continue
        }

        # :attribut: valeur
        if ($trimmed -match '^:([a-zA-Z0-9_-]+)\s*:\s*(.*)$') {
            $attrName = $Matches[1]
            $rawValue = $Matches[2].Trim()

            $attributes[$attrName] = $rawValue
            $attributeSources[$attrName] = $normalizedPath

            [void]$attributeLog.Add(@{
                Name     = $attrName
                RawValue = $rawValue
                File     = $normalizedPath
            })
            continue
        }

        # --- Directives d'inclusion ---
        if ($trimmed -match '^include::(.+?)\[(.*)?\]$') {
            $includePath = $Matches[1]
            $includeOpts = $Matches[2]

            $resolvedPath = Resolve-AttributeValue $includePath

            if ($resolvedPath -match '\{[a-zA-Z0-9_-]+\}') {
                Write-Warning "Chemin d'inclusion non resolu : $resolvedPath (original: $includePath)"
                continue
            }

            if ([System.IO.Path]::IsPathRooted($resolvedPath)) {
                $fullIncludePath = $resolvedPath
            }
            else {
                $fullIncludePath = Join-Path $currentDir $resolvedPath
            }

            $fullIncludePath = $fullIncludePath -replace '/', '\'

            $isOptional = $includeOpts -match 'opts\s*=\s*optional'

            if (Test-Path $fullIncludePath) {
                Process-AdocFile -FilePath $fullIncludePath -BaseDir (Split-Path -Parent $fullIncludePath)
            }
            elseif (-not $isOptional) {
                Write-Warning "Fichier inclus non trouve : $fullIncludePath"
            }
            else {
                $indent2 = "  " * ($script:depth + 1)
                Write-Host "${indent2}  (optionnel, ignore) $fullIncludePath" -ForegroundColor DarkGray
            }
            continue
        }
    }

    $visitedFiles.Remove($normalizedPath) | Out-Null
    $script:depth--
}

# --- Exécution principale ---

Write-Host ""
Write-Host "=== Resolution des attributs AsciiDoc ===" -ForegroundColor Green
Write-Host "Backend cible : $Backend" -ForegroundColor Yellow
Write-Host "Fichier source: $loaderFile" -ForegroundColor Yellow
Write-Host ""

# Traiter le loader
Process-AdocFile -FilePath $loaderFile -BaseDir (Split-Path -Parent $loaderFile)

# Passe finale de résolution
Write-Host ""
Write-Host "=== Resolution finale des valeurs ===" -ForegroundColor Green

$resolvedAttributes = [ordered]@{}
foreach ($key in $attributes.Keys) {
    $resolvedAttributes[$key] = Resolve-AttributeValue $attributes[$key]
}

# --- Construire les groupes par fichier source ---
$groups = [ordered]@{}
foreach ($key in $resolvedAttributes.Keys) {
    $source = $attributeSources[$key]
    $relSource = $source
    if ($source.StartsWith($fwRoot)) {
        $relSource = $source.Substring($fwRoot.Length).TrimStart('\', '/')
    }
    if (-not $groups.Contains($relSource)) {
        $groups[$relSource] = [System.Collections.ArrayList]::new()
    }
    [void]$groups[$relSource].Add(@{ Name = $key; Value = $resolvedAttributes[$key] })
}

# --- Calculer le hash du contenu (sans metadonnees de version) ---
$contentLines = [System.Collections.ArrayList]::new()
foreach ($source in $groups.Keys) {
    foreach ($attr in $groups[$source]) {
        [void]$contentLines.Add(":$($attr.Name): $($attr.Value)")
    }
}
$contentForHash = $contentLines -join "`n"
$sha256 = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($contentForHash))
$newHash = [BitConverter]::ToString($hashBytes) -replace '-', ''

# --- Comparer avec le hash precedent ---
if ($newHash -eq $lastHash) {
    Write-Host ""
    Write-Host "=== Aucun changement detecte ===" -ForegroundColor Yellow
    Write-Host "Le contenu des attributs est identique a la version $lastVersion." -ForegroundColor Yellow
    Write-Host "Aucun fichier genere." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

# --- Contenu different : demander la note de version ---
$newVersion = $lastVersion + 1
$versionDate = Get-Date -Format "yyyy-MM-dd"
Write-Host ""
Write-Host "=== Nouvelle version : $newVersion ===" -ForegroundColor Green
Write-Host ""
$versionNote = Read-Host "Note de version (laisser vide pour aucune note)"

# --- Générer le fichier .adoc ---
$outputLines = [System.Collections.ArrayList]::new()
[void]$outputLines.Add("// Fichier genere automatiquement par resolve-attributes.ps1")
[void]$outputLines.Add("// Ne pas modifier manuellement - ce fichier est ecrase a chaque generation")
[void]$outputLines.Add("//")
[void]$outputLines.Add("// Backend : $Backend")
[void]$outputLines.Add("// Source  : $loaderFile")
[void]$outputLines.Add("// Nombre total d'attributs : $($resolvedAttributes.Count + 3)")
[void]$outputLines.Add("// Hash    : $newHash")
[void]$outputLines.Add("//")
[void]$outputLines.Add("// --- version ---")
[void]$outputLines.Add("//")
[void]$outputLines.Add(":__fw_version_number: $newVersion")
[void]$outputLines.Add(":__fw_version_date: $versionDate")
[void]$outputLines.Add(":__fw_version_note: $versionNote")
foreach ($source in $groups.Keys) {
    [void]$outputLines.Add("//")
    [void]$outputLines.Add("// --- $source ---")
    [void]$outputLines.Add("//")
    foreach ($attr in $groups[$source]) {
        [void]$outputLines.Add(":$($attr.Name): $($attr.Value)")
    }
}

$outputContent = $outputLines -join "`n"

# --- Générer le fichier .json ---
$jsonGroups = [ordered]@{}
foreach ($source in $groups.Keys) {
    $jsonAttrs = [ordered]@{}
    foreach ($attr in $groups[$source]) {
        $jsonAttrs[$attr.Name] = $attr.Value
    }
    $jsonGroups[$source] = $jsonAttrs
}
$jsonObject = [ordered]@{
    adp_fw_version_number = $newVersion
    adp_fw_version_date   = $versionDate
    adp_fw_version_note   = $versionNote
    backend               = $Backend
    hash                  = $newHash
    attributes_count      = $resolvedAttributes.Count + 3
    sources               = $jsonGroups
}
$jsonContent = $jsonObject | ConvertTo-Json -Depth 4

$jsonFile = Join-Path $dumpDir "attributes-dump.json"
$jsonVersionedFile = Join-Path $dumpDir "attributes-dump_v${newVersion}.json"

# --- Écrire les fichiers ---
Set-Content -Path $dumpFile -Value $outputContent -Encoding UTF8 -NoNewline
$versionedFile = Join-Path $dumpDir "attributes-dump_v${newVersion}.adoc"
Set-Content -Path $versionedFile -Value $outputContent -Encoding UTF8 -NoNewline
Set-Content -Path $jsonFile -Value $jsonContent -Encoding UTF8 -NoNewline
Set-Content -Path $jsonVersionedFile -Value $jsonContent -Encoding UTF8 -NoNewline
Set-Content -Path $versionFile -Value $newVersion -Encoding UTF8 -NoNewline
Set-Content -Path $hashFile -Value $newHash -Encoding UTF8 -NoNewline

# --- Résumé ---
Write-Host ""
Write-Host "=== Resultat ===" -ForegroundColor Green
Write-Host "Version         : $newVersion" -ForegroundColor White
Write-Host "Date            : $versionDate" -ForegroundColor White
if ($versionNote) {
    Write-Host "Note            : $versionNote" -ForegroundColor White
}
Write-Host "Hash            : $newHash" -ForegroundColor DarkGray
Write-Host "Attributs       : $($resolvedAttributes.Count + 3)" -ForegroundColor White
Write-Host "Fichier courant : $dumpFile" -ForegroundColor White
Write-Host "Archive adoc    : $versionedFile" -ForegroundColor White
Write-Host "JSON courant    : $jsonFile" -ForegroundColor White
Write-Host "Archive JSON    : $jsonVersionedFile" -ForegroundColor White

# Attributs non résolus
$unresolvedCount = 0
foreach ($key in $resolvedAttributes.Keys) {
    $val = $resolvedAttributes[$key]
    if ($val -match '\{[a-zA-Z0-9_-]+\}') {
        $unresolvedCount++
        if ($ShowUnresolved) {
            Write-Host "  [NON RESOLU] :${key}: ${val}" -ForegroundColor Red
        }
    }
}

if ($unresolvedCount -gt 0) {
    Write-Host "Non resolus     : $unresolvedCount" -ForegroundColor Yellow
    if (-not $ShowUnresolved) {
        Write-Host "  (utiliser -ShowUnresolved pour les afficher)" -ForegroundColor DarkGray
    }
}

Write-Host ""
