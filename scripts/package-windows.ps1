param(
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$BuildNumber = '1',
    [string]$Source = 'build/windows/x64/runner/Release',
    [string]$Output = 'release-assets',
    [switch]$InstallerOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    # Pin the build tool and verify the immutable upstream release before execution.
    $compilerVersion = '6.7.3'
    $compilerChecksum = '9c73c3bae7ed48d44112a0f48e66742c00090bdb5bef71d9d3c056c66e97b732'
    $compilerRoot = Join-Path $projectRoot ".tools/inno-setup-$compilerVersion"
    $compiler = Join-Path $compilerRoot 'ISCC.exe'
    if (-not (Test-Path -LiteralPath $compiler)) {
        $downloadRoot = Join-Path $projectRoot '.tools/downloads'
        New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
        $download = Join-Path $downloadRoot "innosetup-$compilerVersion.exe"
        Invoke-WebRequest -Uri "https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-$compilerVersion.exe" -OutFile $download
        if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $compilerChecksum) {
            throw 'Inno Setup compiler download checksum mismatch'
        }
        $install = Start-Process -FilePath $download -ArgumentList @(
            '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', '/NOICONS', '/TASKS=""',
            ('/DIR="' + $compilerRoot + '"')
        ) -WindowStyle Hidden -Wait -PassThru
        if ($install.ExitCode -ne 0) { throw "Compiler installation failed: $($install.ExitCode)" }
    }
    if (-not $InstallerOnly) {
        python scripts/release.py windows --tag $Tag --build-number $BuildNumber --source $Source --output $Output
        if ($LASTEXITCODE -ne 0) { throw 'Windows portable packaging failed' }
    }
    python scripts/release.py installer --tag $Tag --build-number $BuildNumber --source $Source --output $Output --iscc $compiler
    if ($LASTEXITCODE -ne 0) { throw 'Windows installer packaging failed' }
} finally { Pop-Location }
