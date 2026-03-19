#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installe Claude Code (CLI) dans la VM
.DESCRIPTION
    - Installe Node.js LTS (v22.14.0)
    - Installe Git for Windows (requis pour Git Bash)
    - Installe Claude Code via npm
    - Configure la variable CLAUDE_CODE_GIT_BASH_PATH si necessaire
.NOTES
    Executer DANS la VM, en tant qu'Administrateur
    La VM doit avoir acces a Internet
#>

$ErrorActionPreference = "Stop"

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  LAB AD - Installation Claude Code" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# --- 1. Verifier la connectivite Internet ---
Write-Host "`n[1/5] Verification de la connectivite Internet..." -ForegroundColor Yellow
$ping = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction SilentlyContinue
if (-not $ping) {
    Write-Host "  ERREUR: Pas d'acces Internet!" -ForegroundColor Red
    Write-Host "  Executez 05_Fix-Network.ps1 sur l'hote d'abord." -ForegroundColor Yellow
    exit 1
}
Write-Host "  -> Internet OK." -ForegroundColor Green

# --- 2. Installer Node.js ---
Write-Host "`n[2/5] Installation de Node.js LTS..." -ForegroundColor Yellow

$nodeInstalled = Get-Command node -ErrorAction SilentlyContinue
if ($nodeInstalled) {
    $nodeVersion = & node --version 2>$null
    Write-Host "  -> Node.js deja installe: $nodeVersion" -ForegroundColor Green
} else {
    $nodeUrl = "https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi"
    $nodeInstaller = "$env:TEMP\nodejs.msi"

    Write-Host "  -> Telechargement de Node.js v22.14.0..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $nodeUrl -OutFile $nodeInstaller -UseBasicParsing

    Write-Host "  -> Installation en cours..." -ForegroundColor Gray
    Start-Process msiexec.exe -ArgumentList "/i `"$nodeInstaller`" /quiet /norestart" -Wait

    # Ajouter Node.js au PATH de la session courante
    $nodePath = "C:\Program Files\nodejs"
    if (Test-Path $nodePath) {
        $env:PATH = "$nodePath;$env:PATH"
    }

    $nodeVersion = & node --version 2>$null
    if ($nodeVersion) {
        Write-Host "  -> Node.js $nodeVersion installe." -ForegroundColor Green
    } else {
        Write-Host "  -> ERREUR: Node.js n'a pas pu etre installe." -ForegroundColor Red
        Write-Host "  -> Fermez et rouvrez PowerShell, puis relancez ce script." -ForegroundColor Yellow
        exit 1
    }
}

# --- 3. Installer Git for Windows ---
Write-Host "`n[3/5] Installation de Git for Windows..." -ForegroundColor Yellow

$gitBashPath = "C:\Program Files\Git\bin\bash.exe"
$gitInstalled = Test-Path $gitBashPath

if ($gitInstalled) {
    $gitVersion = & "C:\Program Files\Git\bin\git.exe" --version 2>$null
    Write-Host "  -> Git deja installe: $gitVersion" -ForegroundColor Green
} else {
    $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe"
    $gitInstaller = "$env:TEMP\git-installer.exe"

    Write-Host "  -> Telechargement de Git for Windows..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing

    Write-Host "  -> Installation en cours..." -ForegroundColor Gray
    Start-Process $gitInstaller -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS=icons,ext\reg\shellhere,assoc,assoc_sh" -Wait

    # Ajouter Git au PATH de la session courante
    $gitPath = "C:\Program Files\Git\cmd"
    if (Test-Path $gitPath) {
        $env:PATH = "$gitPath;C:\Program Files\Git\bin;$env:PATH"
    }

    if (Test-Path $gitBashPath) {
        Write-Host "  -> Git for Windows installe (Git Bash disponible)." -ForegroundColor Green
    } else {
        Write-Host "  -> ERREUR: Git Bash introuvable apres installation." -ForegroundColor Red
        Write-Host "  -> Fermez et rouvrez PowerShell, puis relancez ce script." -ForegroundColor Yellow
        exit 1
    }
}

# --- 4. Configurer la variable CLAUDE_CODE_GIT_BASH_PATH ---
Write-Host "`n[4/5] Configuration de l'environnement..." -ForegroundColor Yellow

# Variable de session
$env:CLAUDE_CODE_GIT_BASH_PATH = $gitBashPath
Write-Host "  -> CLAUDE_CODE_GIT_BASH_PATH = $gitBashPath" -ForegroundColor Green

# Variable permanente (Machine)
[System.Environment]::SetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", $gitBashPath, "Machine")
Write-Host "  -> Variable d'environnement definie (permanente)." -ForegroundColor Green

# --- 5. Installer Claude Code ---
Write-Host "`n[5/5] Installation de Claude Code..." -ForegroundColor Yellow

$npmPath = "C:\Program Files\nodejs\npm.cmd"
if (-not (Test-Path $npmPath)) {
    $npmPath = "npm"
}

& $npmPath install -g @anthropic-ai/claude-code 2>&1 | ForEach-Object {
    if ($_ -match "added") { Write-Host "  -> $_" -ForegroundColor Green }
}

# Verifier l'installation
$claudePath = "$env:APPDATA\npm\claude.ps1"
if (Test-Path $claudePath) {
    Write-Host "  -> Claude Code installe avec succes!" -ForegroundColor Green
} else {
    # Essayer de trouver claude
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($claudeCmd) {
        Write-Host "  -> Claude Code installe: $($claudeCmd.Source)" -ForegroundColor Green
    } else {
        Write-Host "  -> Installation terminee. Fermez et rouvrez PowerShell pour utiliser 'claude'." -ForegroundColor Yellow
    }
}

# --- Resume ---
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Claude Code installe avec succes!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Composants installes:" -ForegroundColor White
$nodeV = & node --version 2>$null
Write-Host "    Node.js  : $nodeV"
$npmV = & npm --version 2>$null
Write-Host "    npm      : $npmV"
$gitV = & git --version 2>$null
Write-Host "    Git      : $gitV"
Write-Host "    Claude   : @anthropic-ai/claude-code"
Write-Host ""
Write-Host "  Pour lancer Claude Code:" -ForegroundColor Yellow
Write-Host "    claude" -ForegroundColor White
Write-Host ""
Write-Host "  Si Claude ne se lance pas, fermez et rouvrez" -ForegroundColor Gray
Write-Host "  PowerShell pour rafraichir le PATH." -ForegroundColor Gray
Write-Host ""

Read-Host "Appuyez sur Entree pour terminer"
