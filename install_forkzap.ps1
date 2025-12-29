[CmdletBinding()]
param(
    [string]$Profile = "general",
    [string]$InstallPath = "G:\forkzap"
)

$ErrorActionPreference = "Stop"

function Set-Tls12 {
    $current = [Net.ServicePointManager]::SecurityProtocol
    if (($current -band [Net.SecurityProtocolType]::Tls12) -eq 0) {
        [Net.ServicePointManager]::SecurityProtocol = $current -bor [Net.SecurityProtocolType]::Tls12
    }
}

function Get-LatestAssetUrl {
    param(
        [string]$Owner,
        [string]$Repo,
        [string]$AssetName
    )

    Write-Host "[*] Getting latest release info..."
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases/latest" `
            -Headers @{ "User-Agent" = "forkzap-installer" }
    } catch {
        throw "Failed to query GitHub Releases: $($_.Exception.Message)"
    }

    $asset = $release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
    if (-not $asset) {
        throw "Asset $AssetName was not found in the latest release."
    }

    return $asset.browser_download_url
}

function Get-ProfileName {
    param([System.IO.FileInfo]$File)

    $match = [regex]::Match($File.BaseName, '\(([^)]+)\)')
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    return $File.BaseName
}

function Resolve-Profile {
    param(
        [System.IO.FileInfo[]]$BatFiles,
        [string]$DesiredProfile
    )

    $normalized = $DesiredProfile.Trim()
    $comparison = [System.StringComparison]::OrdinalIgnoreCase

    $exactMatch = $BatFiles | Where-Object {
        (Get-ProfileName $_).Equals($normalized, $comparison)
    } | Select-Object -First 1

    return $exactMatch
}

Set-Tls12

$owner = "andrushikk"
$repo = "zapret-discord-youtube-forkauto-2"
$assetName = "forkzap.zip"

try {
    $downloadUrl = Get-LatestAssetUrl -Owner $owner -Repo $repo -AssetName $assetName
    Write-Host ("[*] Found {0}: {1}" -f $assetName, $downloadUrl)

    if (-not (Test-Path -LiteralPath $InstallPath)) {
        Write-Host ("[*] Creating install directory: {0}" -f $InstallPath)
        New-Item -ItemType Directory -Path $InstallPath | Out-Null
    }

    $tmpZip = Join-Path $env:TEMP $assetName
    Write-Host "[*] Downloading zip..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tmpZip

    Write-Host ("[*] Extracting to {0} ..." -f $InstallPath)
    Expand-Archive -LiteralPath $tmpZip -DestinationPath $InstallPath -Force
    Remove-Item $tmpZip -Force
    Write-Host ("[OK] Files extracted to: {0}" -f $InstallPath)

    $batFiles = Get-ChildItem -Path $InstallPath -Recurse -Filter "*.bat" -File -ErrorAction SilentlyContinue
    if (-not $batFiles) {
        throw "No .bat files were found inside $InstallPath."
    }

    $selectedBat = Resolve-Profile -BatFiles $batFiles -DesiredProfile $Profile
    if ($null -eq $selectedBat) {
        Write-Host ("[X] Could not find a bat file for profile '{0}'." -f $Profile)
        Write-Host "Available profiles:"
        foreach ($bat in $batFiles) {
            Write-Host (" - {0}" -f (Get-ProfileName $bat))
        }
        exit 2
    }

    Write-Host ("[OK] Launching: {0}" -f $selectedBat.FullName)
    Start-Process -FilePath $selectedBat.FullName -WorkingDirectory $selectedBat.DirectoryName -Verb RunAs
} catch {
    Write-Error "[X] $_"
    exit 1
}
