#Requires -RunAsAdministrator
# Copie tous les fichiers ad_lab dans C:\Share\ad_lab sur la VM DC01-LAB

$secPass = ConvertTo-SecureString "Cim22091967!!??" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential(".\Administrator", $secPass)
$scriptsPath = $PSScriptRoot

Write-Host "=== Copie des fichiers dans \\DC01-LAB\Share\ad_lab ===" -ForegroundColor Cyan

# Scripts principaux (.ps1 a la racine)
foreach ($f in (Get-ChildItem $scriptsPath -Filter *.ps1)) {
    Copy-VMFile -VMName DC01-LAB -SourcePath $f.FullName `
        -DestinationPath "C:\Share\ad_lab\$($f.Name)" `
        -CreateFullPath -FileSource Host -Force -ErrorAction SilentlyContinue
    if ($?) { Write-Host "  [OK] $($f.Name)" -ForegroundColor Green }
    else    { Write-Host "  [FAIL] $($f.Name)" -ForegroundColor Red }
}

# populate/
foreach ($f in (Get-ChildItem "$scriptsPath\populate" -Filter *.ps1)) {
    Copy-VMFile -VMName DC01-LAB -SourcePath $f.FullName `
        -DestinationPath "C:\Share\ad_lab\populate\$($f.Name)" `
        -CreateFullPath -FileSource Host -Force -ErrorAction SilentlyContinue
    if ($?) { Write-Host "  [OK] populate/$($f.Name)" -ForegroundColor Green }
    else    { Write-Host "  [FAIL] populate/$($f.Name)" -ForegroundColor Red }
}

# Autres fichiers
foreach ($name in @("DEPLOY.bat","README.md","README.en.md","GUIDE_INSTALLATION.md","LICENSE","VERSION",".gitignore","config.example.ps1")) {
    $src = Join-Path $scriptsPath $name
    if (Test-Path $src) {
        Copy-VMFile -VMName DC01-LAB -SourcePath $src `
            -DestinationPath "C:\Share\ad_lab\$name" `
            -CreateFullPath -FileSource Host -Force -ErrorAction SilentlyContinue
        if ($?) { Write-Host "  [OK] $name" -ForegroundColor Green }
    }
}

Write-Host "`n=== Verification ===" -ForegroundColor Cyan
Invoke-Command -VMName DC01-LAB -Credential $cred -ScriptBlock {
    Get-ChildItem C:\Share\ad_lab -Recurse | Select-Object FullName | Format-Table -AutoSize
}

Write-Host "`nAcces: \\192.168.0.10\Share\ad_lab" -ForegroundColor Green
pause
