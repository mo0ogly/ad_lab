#Requires -RunAsAdministrator
. "$PSScriptRoot\config.ps1"
$secPass = ConvertTo-SecureString $LabPassword -AsPlainText -Force
$cred = New-Object PSCredential('LAB\Administrator', $secPass)

$destDir = "$PSScriptRoot\collects\ADDS\real_data"
New-Item -Path $destDir -ItemType Directory -Force | Out-Null

# Lister et copier les XML depuis la VM
$files = Invoke-Command -VMName 'DC01-LAB' -Credential $cred -ScriptBlock {
    $base = 'C:\Share\collectors_output\collect\AD01\20260320\collect'
    Get-ChildItem $base -Filter '*.xml' -File | ForEach-Object {
        @{ Name = $_.Name; Content = [IO.File]::ReadAllBytes($_.FullName) }
    }
}

$count = 0
foreach ($f in $files) {
    $dest = Join-Path $destDir $f.Name
    [IO.File]::WriteAllBytes($dest, $f.Content)
    $sizeKB = [math]::Round($f.Content.Length / 1KB, 1)
    Write-Host "  [OK] $($f.Name) ($sizeKB KB)"
    $count++
}
Write-Host "`n$count fichiers copies vers $destDir"
