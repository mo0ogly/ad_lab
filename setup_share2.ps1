#Requires -RunAsAdministrator
# Methode 2: Creer share via PS Direct, puis copier via SMB

$VMName = "DC01-LAB"
$secPass = ConvertTo-SecureString "Cim22091967!!??" -AsPlainText -Force

# Trouver le bon credential
$cred = $null
foreach ($user in @(".\Administrator","LAB\Administrator","Administrator")) {
    Write-Host "Test: $user..." -NoNewline
    try {
        $c = New-Object System.Management.Automation.PSCredential($user, $secPass)
        Invoke-Command -VMName $VMName -Credential $c -ScriptBlock { $true } -ErrorAction Stop | Out-Null
        Write-Host " OK" -ForegroundColor Green
        $cred = $c
        break
    } catch { Write-Host " FAIL" -ForegroundColor Red }
}
if (-not $cred) { Write-Host "ERREUR: aucun credential!" -ForegroundColor Red; pause; exit 1 }

# Etape 1: Configurer le share dans la VM
Write-Host "`n=== Configuration share dans la VM ===" -ForegroundColor Cyan
Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    # Desactiver firewall
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
    Write-Host "[OK] Firewall OFF" -ForegroundColor Green

    # Creer dossier
    New-Item -Path "C:\Share\ad_lab\populate" -ItemType Directory -Force | Out-Null
    Write-Host "[OK] C:\Share\ad_lab\populate cree" -ForegroundColor Green

    # NTFS Everyone FullControl
    $acl = Get-Acl "C:\Share"
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone","FullControl","ContainerInherit,ObjectInherit","None","Allow")
    $acl.SetAccessRule($rule)
    Set-Acl "C:\Share" $acl
    Write-Host "[OK] NTFS Everyone FullControl" -ForegroundColor Green

    # Recreer le share
    Remove-SmbShare -Name "Share" -Force -ErrorAction SilentlyContinue
    New-SmbShare -Name "Share" -Path "C:\Share" -FullAccess "Everyone" | Out-Null
    Write-Host "[OK] SMB Share cree" -ForegroundColor Green

    # Activer SMB1 au cas ou (Windows 10 host)
    Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force -ErrorAction SilentlyContinue
    Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] SMB1+SMB2 actives" -ForegroundColor Green

    # Verif
    Get-SmbShare -Name Share | Format-List Name, Path, CurrentUsers, ShareState
}

# Etape 2: Mapper le drive depuis l'hote et copier
Write-Host "`n=== Copie via SMB ===" -ForegroundColor Cyan

# Nettoyer ancien mapping
net use Z: /delete 2>$null

# Mapper
Write-Host "Mapping Z: -> \\192.168.0.10\Share..."
net use Z: "\\192.168.0.10\Share" /user:LAB\Administrator "Cim22091967!!??"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Essai avec .\Administrator..." -ForegroundColor Yellow
    net use Z: "\\192.168.0.10\Share" /user:Administrator "Cim22091967!!??"
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERREUR] Impossible de mapper le share!" -ForegroundColor Red
    Write-Host "On va copier via une session PS Direct a la place..." -ForegroundColor Yellow

    # Methode alternative: lire les fichiers et les ecrire via PS Direct
    $srcPath = $PSScriptRoot

    # Copier chaque fichier via Invoke-Command
    $files = @()
    Get-ChildItem $srcPath -Filter "*.ps1" -File | Where-Object { $_.Name -notin @("setup_share.ps1","setup_share2.ps1","copy_to_share.ps1") } | ForEach-Object { $files += @{Name=$_.Name; Path=$_.FullName; Dest="C:\Share\ad_lab\$($_.Name)"} }
    Get-ChildItem "$srcPath\populate" -Filter "*.ps1" -File | ForEach-Object { $files += @{Name="populate/$($_.Name)"; Path=$_.FullName; Dest="C:\Share\ad_lab\populate\$($_.Name)"} }
    foreach ($name in @("DEPLOY.bat","README.md","README.en.md","GUIDE_INSTALLATION.md","LICENSE","VERSION","config.example.ps1")) {
        $p = Join-Path $srcPath $name
        if (Test-Path $p) { $files += @{Name=$name; Path=$p; Dest="C:\Share\ad_lab\$name"} }
    }

    foreach ($f in $files) {
        try {
            $content = [System.IO.File]::ReadAllBytes($f.Path)
            Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
                param($dest, $bytes)
                $dir = Split-Path $dest -Parent
                if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
                [System.IO.File]::WriteAllBytes($dest, $bytes)
            } -ArgumentList $f.Dest, $content
            Write-Host "  [OK] $($f.Name)" -ForegroundColor Green
        } catch {
            Write-Host "  [FAIL] $($f.Name) - $_" -ForegroundColor Red
        }
    }
} else {
    Write-Host "[OK] Drive Z: mappe" -ForegroundColor Green
    $srcPath = $PSScriptRoot

    New-Item -Path "Z:\ad_lab\populate" -ItemType Directory -Force | Out-Null

    Get-ChildItem $srcPath -Filter "*.ps1" -File | Where-Object { $_.Name -notin @("setup_share.ps1","setup_share2.ps1","copy_to_share.ps1") } | ForEach-Object {
        Copy-Item $_.FullName "Z:\ad_lab\$($_.Name)" -Force
        Write-Host "  [OK] $($_.Name)" -ForegroundColor Green
    }
    Get-ChildItem "$srcPath\populate" -Filter "*.ps1" -File | ForEach-Object {
        Copy-Item $_.FullName "Z:\ad_lab\populate\$($_.Name)" -Force
        Write-Host "  [OK] populate/$($_.Name)" -ForegroundColor Green
    }
    foreach ($name in @("DEPLOY.bat","README.md","README.en.md","GUIDE_INSTALLATION.md","LICENSE","VERSION","config.example.ps1")) {
        $p = Join-Path $srcPath $name
        if (Test-Path $p) { Copy-Item $p "Z:\ad_lab\$name" -Force; Write-Host "  [OK] $name" -ForegroundColor Green }
    }

    net use Z: /delete 2>$null
}

# Verif finale
Write-Host "`n=== Contenu final ===" -ForegroundColor Cyan
Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    $items = Get-ChildItem C:\Share\ad_lab -Recurse -File
    $items | ForEach-Object { Write-Host "  $($_.FullName) ($([math]::Round($_.Length/1KB,1)) KB)" }
    Write-Host "`nTotal: $($items.Count) fichiers" -ForegroundColor Green
}

Write-Host "`nAcces: \\192.168.0.10\Share" -ForegroundColor Green
pause
