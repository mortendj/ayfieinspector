<#
.SYNOPSIS
Builds a distributable zip package of AyfieInspector, with Winspect bundled inside it.

.DESCRIPTION
Packages Invoke-AyfieInspector.ps1 + src/ together with a fresh copy of Winspect (Invoke-
Winspect.ps1 + src/, read from a sibling Winspect repo at build time) into
dist/ayfieinspector-vX.Y.Z.zip, with the version read from src/Constants.ps1 so the package name
can't drift out of sync with the code.

The zip contains a single top-level "AyfieInspector" folder (avoids scattering loose files
wherever it's extracted to), with Winspect nested inside it as a subordinate dependency rather
than a sibling - AyfieInspector is the one entry point a user needs to find; Winspect is an
implementation detail underneath it. This is the exact relative layout Invoke-AyfieInspector.ps1's
own -winspectPath default already expects, so a customer extracting the zip needs no extra
configuration to run it.

Winspect's src/ stays single-sourced in the Winspect repo - this only ever copies a fresh snapshot
of it at build time, it never becomes a second, permanently-maintained fork.
#>

[CmdletBinding()]
param(
    [string]$winspectRepoPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "Winspect")
)

$repoRoot = $PSScriptRoot
. (Join-Path $repoRoot "src\Constants.ps1")

if (-not (Test-Path $winspectRepoPath)) {
    Write-Error "Winspect repo not found at '$winspectRepoPath'. Pass -winspectRepoPath explicitly if it lives elsewhere."
    exit 1
}

$packageName = "ayfieinspector-v$AYFIE_INSPECTOR_VERSION"
$distDir = Join-Path $repoRoot "dist"
$zipPath = Join-Path $distDir "$packageName.zip"
$stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) $packageName
$packageRoot = Join-Path $stagingDir "AyfieInspector"
$winspectRoot = Join-Path $packageRoot "Winspect"

if (Test-Path $stagingDir) {
    Remove-Item -Path $stagingDir -Recurse -Force
}
New-Item -ItemType Directory -Path $packageRoot | Out-Null
New-Item -ItemType Directory -Path $winspectRoot | Out-Null

Copy-Item -Path (Join-Path $repoRoot "Invoke-AyfieInspector.ps1") -Destination $packageRoot
Copy-Item -Path (Join-Path $repoRoot "src") -Destination $packageRoot -Recurse

# Only what Invoke-Winspect.ps1 actually needs to run is copied - same exclusions Winspect's own
# build script uses (no Tests/, no old-*, no README/LICENSE - this is an internal bundling, not a
# standalone redistribution of Winspect itself).
Copy-Item -Path (Join-Path $winspectRepoPath "Invoke-Winspect.ps1") -Destination $winspectRoot
Copy-Item -Path (Join-Path $winspectRepoPath "src") -Destination $winspectRoot -Recurse

if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir | Out-Null
}
if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}
Compress-Archive -Path $packageRoot -DestinationPath $zipPath

Remove-Item -Path $stagingDir -Recurse -Force

Write-Host "Built $zipPath"
