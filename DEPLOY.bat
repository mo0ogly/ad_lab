@echo off
echo ================================================
echo   LAB ACTIVE DIRECTORY - Deploiement Complet
echo ================================================
echo.
echo   === INFRASTRUCTURE PRINCIPALE (DC01) ===
echo.
echo   [ETAPE 1] 01_Create-VM.ps1
echo     ^> Execute sur ta MACHINE HOTE (Windows 11)
echo     ^> Cree la VM Hyper-V + reseau
echo     ^> Necessite l'ISO Windows Server 2022
echo.
echo   [ETAPE 2] 02_Install-ADDS.ps1
echo     ^> Execute DANS la VM (Windows Server)
echo     ^> Installe AD DS + DNS + DHCP
echo     ^> Promeut en Domain Controller (lab.local)
echo     ^> Necessite 2 redemarrages
echo.
echo   [ETAPE 3] 03_Install-Services.ps1
echo     ^> Execute DANS la VM (apres reboot)
echo     ^> Installe 15+ services (PKI, IIS, DFS, RDS, NPS...)
echo.
echo   [ETAPE 4] 04_Populate-AD.ps1
echo     ^> Execute DANS la VM
echo     ^> Cree 80+ users, groupes, OUs, GPOs, comptes admin
echo     ^> Inclut 04a-04m : 85+ anomalies pour LIA-Scan
echo.
echo   === INFRASTRUCTURE AVANCEE (RODC + Trust) ===
echo.
echo   [ETAPE 5] 05_Deploy-SecondDC.ps1
echo     ^> Execute sur ta MACHINE HOTE
echo     ^> Cree 2 VMs : DC02-LAB (RODC) + DC-PARTNER (partner.local)
echo     ^> Genere les scripts d'installation dans C:\HyperV\setup-scripts\
echo.
echo   [ETAPE 5a] A2_Install-RODC.ps1
echo     ^> Execute DANS DC02-LAB
echo     ^> Promeut DC02 en RODC dans lab.local
echo.
echo   [ETAPE 5b] B2_Install-PartnerForest.ps1
echo     ^> Execute DANS DC-PARTNER
echo     ^> Cree la foret partner.local
echo.
echo   [ETAPE 5c] B3_PostConfig-Partner.ps1
echo     ^> Execute DANS DC-PARTNER (apres promotion)
echo     ^> DNS conditionnel + utilisateurs partenaires
echo.
echo   [ETAPE 5d] B4_Setup-Trust-Vulns.ps1
echo     ^> Execute SUR DC01
echo     ^> Trust bidirectionnel + anomalies (SID filtering OFF,
echo       TGT delegation, RC4 only, RODC PRP permissive)
echo.
echo ================================================
echo   COLLECTEURS COUVERTS : 42/42
echo   ANOMALIES TOTALES    : 90+
echo ================================================
echo.
echo   Pour commencer, ouvre PowerShell en Admin et lance:
echo   .\01_Create-VM.ps1
echo.
pause
