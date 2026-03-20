# fix_yaml_duplicates.ps1
# Removes duplicate top-level YAML keys from rule files.
# Keeps the FIRST occurrence, removes the SECOND (and its nested content).

param(
    [string]$AddsDir = "C:\Users\pizzif\Documents\GitHub\lia-security-platform-v2\lia_rules\rule_analysis\ADDS"
)

$topLevelKeyPattern = '^[a-z_]+:'

$files = Get-ChildItem -Path $AddsDir -Filter "*.yml" -Recurse | Where-Object { $_.Name -notlike "README*" }

Write-Host "Scanning $($files.Count) YAML files in $AddsDir ..." -ForegroundColor Cyan

$totalFixedFiles = 0
$totalRemovedBlocks = 0

foreach ($file in $files) {
    $lines = Get-Content -Path $file.FullName -Encoding UTF8
    $seenKeys = @{}
    $outputLines = [System.Collections.Generic.List[string]]::new()
    $skipping = $false
    $removedInFile = 0

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # Check if this is a top-level key (no leading whitespace)
        if ($line -match $topLevelKeyPattern -and $line -notmatch '^\s') {
            # Extract the key name
            $key = ($line -split ':')[0]

            if ($seenKeys.ContainsKey($key)) {
                # Duplicate found - start skipping
                $skipping = $true
                $removedInFile++
                continue
            }
            else {
                # First occurrence - keep it
                $seenKeys[$key] = $true
                $skipping = $false
                $outputLines.Add($line)
            }
        }
        elseif ($skipping) {
            # We are inside a duplicate block - skip indented/empty lines
            # If this line is indented or empty, it belongs to the duplicate block
            if ($line -match '^\s' -or $line -match '^\s*$') {
                continue
            }
            else {
                # Non-indented, non-empty line that is a new top-level key
                # This means the duplicate block ended - process this line
                $skipping = $false
                $key = ($line -split ':')[0]
                if ($seenKeys.ContainsKey($key)) {
                    $skipping = $true
                    $removedInFile++
                    continue
                }
                else {
                    $seenKeys[$key] = $true
                    $outputLines.Add($line)
                }
            }
        }
        else {
            # Normal line (indented content of a kept block, or non-key line)
            $outputLines.Add($line)
        }
    }

    if ($removedInFile -gt 0) {
        # Write cleaned content back (preserve UTF-8 without BOM)
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllLines($file.FullName, $outputLines.ToArray(), $utf8NoBom)
        $totalFixedFiles++
        $totalRemovedBlocks += $removedInFile
        Write-Host "[FIXED] $($file.Name) - removed $removedInFile duplicate block(s)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "===== SUMMARY =====" -ForegroundColor Green
Write-Host "Files scanned:  $($files.Count)"
Write-Host "Files fixed:    $totalFixedFiles"
Write-Host "Blocks removed: $totalRemovedBlocks"
