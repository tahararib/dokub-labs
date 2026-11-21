# ============================================================
# inventaire-master.ps1 — Master DOKUB : inventaire AVANT nettoyage
# Capability Forge / Tahar ARIB
#
# LECTURE SEULE : ce script ne modifie et ne supprime rien.
# Il écrit un rapport dans C:\dokub\inventaire-master.txt
#
# Exécution (Windows PowerShell en administrateur) :
#   powershell -ExecutionPolicy Bypass -File .\inventaire-master.ps1
# ============================================================

#Requires -RunAsAdministrator
$ErrorActionPreference = "Continue"
$env:WSL_UTF8 = "1"
$out = "C:\dokub\inventaire-master.txt"
New-Item -ItemType Directory -Force -Path C:\dokub | Out-Null

function Section { param([string]$t) "`n==================== $t ====================" }

& {
    Section "Machine"
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    "Système : $($os.Caption) $($os.Version)"
    "RAM : $([math]::Round($cs.TotalPhysicalMemory/1GB)) Go ; CPU logiques : $($cs.NumberOfLogicalProcessors)"
    "RAM libre : $([math]::Round($os.FreePhysicalMemory/1MB,1)) Go"

    Section "Disques"
    Get-PSDrive -PSProvider FileSystem | Where-Object Used -ne $null |
        Select-Object Name, @{n='Utilisé_Go';e={[math]::Round($_.Used/1GB,1)}}, @{n='Libre_Go';e={[math]::Round($_.Free/1GB,1)}} |
        Format-Table -AutoSize | Out-String

    Section "Distributions WSL"
    wsl -l -v

    Section "Fichiers disque des distributions WSL (taille)"
    Get-ChildItem "$env:LOCALAPPDATA\Packages", "$env:LOCALAPPDATA\wsl" -Recurse -Filter ext4.vhdx -ErrorAction SilentlyContinue |
        Select-Object @{n='Go';e={[math]::Round($_.Length/1GB,1)}}, FullName | Format-Table -AutoSize | Out-String -Width 250

    Section "Machines virtuelles Hyper-V"
    if (Get-Command Get-VM -ErrorAction SilentlyContinue) { Get-VM | Select-Object Name, State, MemoryAssigned, Path | Format-Table -AutoSize | Out-String -Width 250 }
    else { "Module Hyper-V absent (pas de VM Hyper-V gérable ici)" }

    Section "Autres hyperviseurs (VirtualBox, VMware) : fichiers de VM trouvés"
    Get-ChildItem C:\Users -Recurse -Include *.vbox, *.vmx, *.vdi, *.vmdk -ErrorAction SilentlyContinue |
        Select-Object @{n='Go';e={[math]::Round($_.Length/1GB,1)}}, FullName | Format-Table -AutoSize | Out-String -Width 250

    Section "Logiciels installés (taille estimée)"
    Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*,
                     HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*,
                     HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
        Select-Object DisplayName, DisplayVersion, Publisher, @{n='Mo';e={[math]::Round($_.EstimatedSize/1KB)}} |
        Sort-Object DisplayName -Unique | Format-Table -AutoSize | Out-String -Width 250

    Section "Services automatiques hors Windows (en cours ou non)"
    Get-CimInstance Win32_Service |
        Where-Object { $_.StartMode -eq "Auto" -and $_.PathName -notmatch "\\Windows\\" } |
        Select-Object Name, DisplayName, State, PathName | Format-Table -AutoSize | Out-String -Width 300

    Section "Programmes lancés au démarrage"
    Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, User | Format-Table -AutoSize | Out-String -Width 250

    Section "Fonctionnalités Windows de virtualisation"
    foreach ($f in "Microsoft-Hyper-V-All", "Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform", "Containers") {
        $s = (Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue).State
        "{0,-40} {1}" -f $f, $s
    }

    Section "Plus gros dossiers de C:\ (1er niveau)"
    Get-ChildItem C:\ -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $size = (Get-ChildItem $_.FullName -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        [pscustomobject]@{ Go = [math]::Round($size/1GB,1); Dossier = $_.FullName }
    } | Sort-Object Go -Descending | Select-Object -First 15 | Format-Table -AutoSize | Out-String
} *>&1 | Out-File -FilePath $out -Encoding utf8 -Width 300

Write-Host "Rapport écrit : $out" -ForegroundColor Green
