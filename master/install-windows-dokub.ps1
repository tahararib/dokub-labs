# ============================================================
# install-windows-dokub.ps1 — Master DOKUB « Kubernetes, les essentiels »
# Capability Forge / Tahar ARIB
#
# Cible : Windows 10 22H2 (build 19045) ou Windows 11, 64 bits.
# Rôle  : la partie Windows se limite à WSL2 + Ubuntu 24.04 et à son
#         dimensionnement. Toute la pile (Docker CE, kind, kubectl, Helm…)
#         est installée DANS Ubuntu par install-wsl2-dokub.sh.
#         Aucun Docker Desktop.
#
# Exécution (Windows PowerShell en administrateur) :
#   powershell -ExecutionPolicy Bypass -File .\install-windows-dokub.ps1
# Une seule étape :
#   powershell -ExecutionPolicy Bypass -File .\install-windows-dokub.ps1 -Step step_03_wslconfig
#
# Rejouable : chaque étape vérifie l'état avant d'agir.
# ============================================================

#Requires -RunAsAdministrator
param([string]$Step = "all")

$ErrorActionPreference = "Stop"
# wsl.exe écrit en UTF-16 par défaut, ce qui casse les comparaisons de texte ;
# WSL_UTF8=1 lui fait écrire de l'UTF-8 (reconnu par le WSL du Store, installé à l'étape 02).
$env:WSL_UTF8 = "1"

$Distro   = "Ubuntu-24.04"     # version figée : le nom générique « Ubuntu » change de version avec le temps
$Features = @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")

function Write-Step { param([string]$m) Write-Host "`n$m" -ForegroundColor Cyan }
function Write-OK   { param([string]$m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host "  [KO] $m" -ForegroundColor Red }

# Sous Windows PowerShell 5.1 (Windows 10), Get-WindowsOptionalFeature n'accepte
# qu'UN nom de fonctionnalité par appel : on interroge donc une fonctionnalité à la fois.
function Get-FeatureState { param([string]$Name)
    (Get-WindowsOptionalFeature -Online -FeatureName $Name).State
}

# ────────────────────────────────────────────────
function step_01_features {
    Write-Step "[01/05] Fonctionnalités Windows nécessaires à WSL2..."

    $build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
    if ($build -lt 19041) { Write-Err "Build $build : WSL2 exige au minimum la build 19041."; exit 1 }
    Write-OK "Build Windows $build compatible WSL2"

    $rebootNeeded = $false
    foreach ($f in $Features) {
        if ((Get-FeatureState $f) -eq "Enabled") {
            Write-OK "$f déjà activée"
        } else {
            # Enable-WindowsOptionalFeature : module DISM de Windows ; -NoRestart pour piloter le redémarrage nous-mêmes
            Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart | Out-Null
            Write-OK "$f activée"
            $rebootNeeded = $true
        }
    }

    if ($rebootNeeded) {
        Write-Warn "Redémarrer Windows maintenant, puis relancer le script : il reprendra à l'étape 02."
        exit 0
    }
}

# ────────────────────────────────────────────────
function step_02_wsl_ubuntu {
    Write-Step "[02/05] WSL (version Store) et $Distro..."

    # wsl --update remplace le WSL intégré à Windows 10 par la version distribuée
    # par Microsoft (Store/GitHub) : noyau récent, systemd, catalogue complet des distributions.
    wsl --update
    if ($LASTEXITCODE -ne 0) { Write-Err "wsl --update a échoué (accès réseau au Store/GitHub ?)"; exit 1 }
    wsl --set-default-version 2 | Out-Null
    Write-OK "WSL à jour, version 2 par défaut"
    wsl --version

    $installed = (wsl -l -q 2>$null) -join " "
    if ($installed -match [regex]::Escape($Distro)) {
        Write-OK "$Distro déjà installée"
        return
    }

    $catalog = (wsl --list --online 2>$null) -join " "
    if ($catalog -notmatch [regex]::Escape($Distro)) {
        Write-Err "$Distro absente du catalogue WSL de cette machine."
        Write-Warn "Copier la sortie de « wsl --list --online » au formateur ; repli prévu : import de l'image .wsl officielle de Canonical."
        exit 1
    }

    # --no-launch : installe sans ouvrir la console ; le compte Linux est créé au 1er lancement.
    wsl --install -d $Distro --no-launch
    if ($LASTEXITCODE -ne 0) { Write-Err "Installation de $Distro en échec"; exit 1 }
    Write-OK "$Distro installée"
    Write-Warn "Lancer « wsl -d $Distro » une première fois pour créer le compte Linux, puis passer à l'étape 03."
}

# ────────────────────────────────────────────────
function step_03_wslconfig {
    Write-Step "[03/05] Dimensionnement de WSL2 (.wslconfig)..."

    # Win32_ComputerSystem : classe CIM de Windows qui expose RAM et processeurs logiques.
    $cs    = Get-CimInstance Win32_ComputerSystem
    $ramGB = [math]::Floor($cs.TotalPhysicalMemory / 1GB)
    $cpu   = $cs.NumberOfLogicalProcessors

    # WSL2 prend par défaut 50 % de la RAM. On lui en donne 75 % (minimum 4 Go) :
    # le cluster kind et les pods de taskboard tournent tous dans WSL2 ; Windows
    # ne garde que le navigateur et le terminal.
    $wslGB = [math]::Max(4, [math]::Floor($ramGB * 0.75))

    Write-Host "  RAM physique : $ramGB Go  -> WSL2 : $wslGB Go"
    Write-Host "  CPU logiques : $cpu        -> WSL2 : $cpu"
    if ($cpu -lt 8) { Write-Warn "$cpu CPU : marge réduite pour les démarrages JVM et le lab de montée en charge (à mesurer au dry run)." }

    $content = @"
[wsl2]
# Mémoire et processeurs alloués à la machine virtuelle WSL2
memory=${wslGB}GB
processors=$cpu
# Swap de secours pour absorber les pics pendant les labs de montée en charge
swap=8GB
"@

    $path = Join-Path $env:USERPROFILE ".wslconfig"
    Set-Content -Path $path -Value $content -Encoding ascii
    Write-OK ".wslconfig écrit dans $path"
    Write-Warn "Le fichier est lu dans le profil du compte qui lance le script : utiliser le même compte que celui des participants."

    # Le fichier n'est lu qu'au démarrage de la VM WSL2 : on l'arrête pour qu'il soit pris en compte.
    wsl --shutdown
    Write-OK "WSL2 arrêté ; la configuration s'appliquera au prochain lancement d'Ubuntu"
}

# ────────────────────────────────────────────────
# Étape facultative : Windows 10 n'a ni Windows Terminal ni VS Code, et souvent pas winget.
# On télécharge donc les installateurs officiels directement (GitHub pour Terminal,
# serveur de mise à jour Microsoft pour VS Code). Installation pour TOUS les comptes
# du poste : les participants des postes clonés les trouvent sans rien faire.
function step_04_optional_tools {
    Write-Step "[04/05] Outils Windows facultatifs (Windows Terminal, VS Code)..."

    # PowerShell 5.1 : TLS 1.2 obligatoire pour GitHub ; la barre de progression
    # d'Invoke-WebRequest ralentit énormément les téléchargements, on la coupe.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = "SilentlyContinue"
    $work = "C:\dokub\outils"
    New-Item -ItemType Directory -Force -Path $work | Out-Null

    # ── Windows Terminal : kit d'installation hors Store publié sur GitHub ──
    if (Get-AppxPackage -AllUsers *WindowsTerminal*) {
        Write-OK "Windows Terminal déjà installé"
    } else {
        $rel   = Invoke-RestMethod "https://api.github.com/repos/microsoft/terminal/releases/latest"
        $asset = $rel.assets | Where-Object name -like "*msixbundle_Windows10_PreinstallKit.zip" | Select-Object -First 1
        if (-not $asset) { Write-Err "Kit Windows 10 introuvable dans la dernière version de Windows Terminal"; return }
        Write-Host "  -> téléchargement de $($asset.name)"
        $zip = Join-Path $work $asset.name
        Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
        $kit = Join-Path $work "terminal-kit"
        Expand-Archive $zip -DestinationPath $kit -Force

        $bundle  = (Get-ChildItem $kit -Recurse -Filter *.msixbundle | Select-Object -First 1).FullName
        $license = (Get-ChildItem $kit -Recurse -Filter *License*.xml | Select-Object -First 1).FullName
        $deps    = @(Get-ChildItem $kit -Recurse -Filter *.appx | Where-Object Name -match "x64" | ForEach-Object FullName)
        Write-Host "  paquet     : $bundle"
        Write-Host "  licence    : $license"
        Write-Host "  dépendances: $($deps -join ', ')"
        if (-not $bundle -or -not $license -or $deps.Count -lt 1) { Write-Err "Contenu du kit inattendu (voir $kit)"; return }

        # Add-AppxProvisionedPackage : installe le paquet pour tous les comptes (actuels et futurs)
        Add-AppxProvisionedPackage -Online -PackagePath $bundle -LicensePath $license -DependencyPackagePath $deps | Out-Null
        # Activation immédiate pour le compte courant (sinon : à la prochaine ouverture de session)
        Get-AppxPackage -AllUsers *WindowsTerminal* | ForEach-Object {
            Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppxManifest.xml"
        }
        if (Get-AppxPackage *WindowsTerminal*) { Write-OK "Windows Terminal installé ($($rel.tag_name))" }
        else { Write-Warn "Windows Terminal installé pour la machine ; il apparaîtra à la prochaine ouverture de session" }
    }

    # ── VS Code : installateur « système » (pour tous les comptes) ──
    $codeExe = "C:\Program Files\Microsoft VS Code\bin\code.cmd"
    if (Test-Path $codeExe) {
        Write-OK "VS Code déjà installé"
    } else {
        $setup = Join-Path $work "VSCodeSetup-x64.exe"
        Write-Host "  -> téléchargement de VS Code (installateur système x64)"
        Invoke-WebRequest "https://update.code.visualstudio.com/latest/win32-x64/stable" -OutFile $setup -UseBasicParsing
        # /VERYSILENT : sans fenêtre ; addtopath : commande « code » dans le PATH ; !runcode : ne pas lancer VS Code à la fin
        Start-Process $setup -ArgumentList '/VERYSILENT', '/NORESTART', '/MERGETASKS=!runcode,addtopath' -Wait
        if (Test-Path $codeExe) { Write-OK "VS Code installé" } else { Write-Err "Installation de VS Code en échec"; return }
    }

    # Extensions VS Code utiles aux labs (installées pour le compte courant)
    foreach ($e in @("ms-vscode-remote.remote-wsl",                   # ouvrir les dossiers situés dans Ubuntu
                     "ms-kubernetes-tools.vscode-kubernetes-tools",   # complétion des manifestes
                     "redhat.vscode-yaml")) {                         # validation YAML par schéma Kubernetes
        & $codeExe --install-extension $e --force | Out-Null
        Write-OK "extension $e"
    }

    Write-Host ""
    Write-OK "Lancement : menu Démarrer > « Terminal » ; ou : explorer.exe shell:AppsFolder\Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"
}

# ────────────────────────────────────────────────
function step_hosts {
    Write-Step "[hosts] Nom taskboard.local (lab 6, Gateway) dans le fichier hosts de Windows..."
    $h = "$env:SystemRoot\System32\drivers\etc\hosts"
    if (Select-String -Path $h -Pattern '^\s*127\.0\.0\.1\s+taskboard\.local\b' -Quiet) {
        Write-OK "déjà présent : 127.0.0.1 taskboard.local"
    } else {
        Add-Content -Path $h -Value "`r`n127.0.0.1 taskboard.local" -Encoding ASCII
        ipconfig /flushdns | Out-Null
        Write-OK "ajouté : 127.0.0.1 taskboard.local"
    }
}

function step_05_validate {
    Write-Step "[05/05] Validation de la partie Windows..."
    $script:ok = 0; $script:ko = 0
    function Test-Item { param([string]$name, [bool]$cond)
        if ($cond) { Write-OK $name; $script:ok++ } else { Write-Err $name; $script:ko++ }
    }

    foreach ($f in $Features) { Test-Item "$f activée" ((Get-FeatureState $f) -eq "Enabled") }

    $list = (wsl -l -v 2>$null) -join "`n"
    Test-Item "$Distro installée en WSL version 2" ($list -match ([regex]::Escape($Distro) + "\s+\S+\s+2"))
    Test-Item ".wslconfig présent" (Test-Path (Join-Path $env:USERPROFILE ".wslconfig"))

    Write-Host "`n  Réussis : $script:ok / Échoués : $script:ko"
    if ($script:ko -eq 0) {
        Write-OK "Partie Windows prête. Suite : copier install-wsl2-dokub.sh dans Ubuntu et l'exécuter."
    } else {
        Write-Warn "Relancer les étapes en échec (redémarrage nécessaire après l'étape 01)."
    }
}

# ────────────────────────────────────────────────
# L'étape 04 (facultative) n'est pas dans l'enchaînement par défaut.
$allSteps = @("step_01_features", "step_02_wsl_ubuntu", "step_03_wslconfig", "step_hosts", "step_05_validate")
$knownSteps = $allSteps + "step_04_optional_tools"

if ($Step -eq "all") {
    foreach ($s in $allSteps) { & $s }
} elseif ($knownSteps -contains $Step) {
    & $Step
} else {
    Write-Err "Étape inconnue : $Step"
    Write-Host "Étapes disponibles : $($knownSteps -join ', ')"
    exit 1
}
