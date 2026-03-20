#Requires -RunAsAdministrator
# Cree le partage SMB sur DC01-LAB et y copie les fichiers ad_lab

param(
    [string]$VMName = "DC01-LAB"
)

$secPass = ConvertTo-SecureString "Cim22091967!!??" -AsPlainText -Force

# Essayer les deux credentials
$creds = @(
    (New-Object System.Management.Automation.PSCredential(".\Administrator", $secPass)),
    (New-Object System.Management.Automation.PSCredential("LAB\Administrator", $secPass)),
    (New-Object System.Management.Automation.PSCredential("Administrator", $secPass))
)

$cred = $null
foreach ($c in $creds) {
    Write-Host "Test: $($c.UserName)..." -NoNewline
    try {
        Invoke-Command -VMName $VMName -Credential $c -ScriptBlock { hostname } -ErrorAction Stop | Out-Null
        Write-Host " OK" -ForegroundColor Green
        $cred = $c
        break
    } catch {
        Write-Host " FAIL" -ForegroundColor Red
    }
}

if (-not $cred) {
    Write-Host "[ERREUR] Aucun credential ne fonctionne!" -ForegroundColor Red
    pause
    exit 1
}

Write-Host "`n=== Configuration du partage dans la VM ===" -ForegroundColor Cyan

# Etape 1: Creer le share dans la VM
Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    # Creer le dossier
    if (-not (Test-Path "C:\Share")) {
        New-Item -Path "C:\Share" -ItemType Directory -Force | Out-Null
        Write-Host "[OK] C:\Share cree" -ForegroundColor Green
    }
    if (-not (Test-Path "C:\Share\ad_lab")) {
        New-Item -Path "C:\Share\ad_lab" -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path "C:\Share\ad_lab\populate")) {
        New-Item -Path "C:\Share\ad_lab\populate" -ItemType Directory -Force | Out-Null
    }

    # Supprimer ancien share si existe
    Remove-SmbShare -Name "Share" -Force -ErrorAction SilentlyContinue

    # Creer le share
    New-SmbShare -Name "Share" -Path "C:\Share" -FullAccess "Everyone" -Description "Partage Lab AD" | Out-Null
    Write-Host "[OK] Share SMB cree" -ForegroundColor Green

    # Permissions NTFS
    $acl = Get-Acl "C:\Share"
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone","FullControl","ContainerInherit,ObjectInherit","None","Allow")
    $acl.SetAccessRule($rule)
    Set-Acl "C:\Share" $acl
    Write-Host "[OK] NTFS Everyone FullControl" -ForegroundColor Green

    # Firewall - activer File and Printer Sharing
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
    Write-Host "[OK] Firewall desactive" -ForegroundColor Green

    # Verif
    Write-Host "`nPartages:"
    Get-SmbShare | Where-Object { $_.Name -ne "IPC$" -and $_.Name -ne "C$" -and $_.Name -ne "ADMIN$" -and $_.Name -ne "NETLOGON" -and $_.Name -ne "SYSVOL" } | Format-Table Name, Path, Description -AutoSize
}

# Etape 2: Copier les fichiers via Copy-VMFile
Write-Host "`n=== Copie des fichiers ===" -ForegroundColor Cyan
$srcPath = $PSScriptRoot

# Scripts racine
foreach ($f in (Get-ChildItem $srcPath -Filter "*.ps1" -File)) {
    if ($f.Name -eq "setup_share.ps1" -or $f.Name -eq "copy_to_share.ps1") { continue }
    try {
        Copy-VMFile -VMName $VMName -SourcePath $f.FullName -DestinationPath "C:\Share\ad_lab\$($f.Name)" -CreateFullPath -FileSource Host -Force
        Write-Host "  [OK] $($f.Name)" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] $($f.Name) - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Autres fichiers
foreach ($name in @("DEPLOY.bat","README.md","README.en.md","GUIDE_INSTALLATION.md","LICENSE","VERSION","config.example.ps1")) {
    $src = Join-Path $srcPath $name
    if (Test-Path $src) {
        try {
            Copy-VMFile -VMName $VMName -SourcePath $src -DestinationPath "C:\Share\ad_lab\$name" -CreateFullPath -FileSource Host -Force
            Write-Host "  [OK] $name" -ForegroundColor Green
        } catch {
            Write-Host "  [FAIL] $name - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# populate/
foreach ($f in (Get-ChildItem "$srcPath\populate" -Filter "*.ps1" -File)) {
    try {
        Copy-VMFile -VMName $VMName -SourcePath $f.FullName -DestinationPath "C:\Share\ad_lab\populate\$($f.Name)" -CreateFullPath -FileSource Host -Force
        Write-Host "  [OK] populate/$($f.Name)" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] populate/$($f.Name) - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Verif finale
Write-Host "`n=== Contenu de C:\Share\ad_lab ===" -ForegroundColor Cyan
Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    Get-ChildItem C:\Share\ad_lab -Recurse | Select-Object FullName | Format-Table -AutoSize
}

Write-Host "`nAcces depuis l'hote: \\192.168.0.10\Share" -ForegroundColor Green
pause
