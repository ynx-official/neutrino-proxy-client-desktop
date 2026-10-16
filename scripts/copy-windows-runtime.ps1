param([string]$Bundle = 'build/windows/x64/runner/Release')

$ErrorActionPreference = 'Stop'
$locator = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = & $locator -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $installation) {
    throw 'Visual Studio C++ tools are required to locate the redistributable runtime.'
}
$redistRoot = Join-Path $installation 'VC/Redist/MSVC'
$version = Get-ChildItem -LiteralPath $redistRoot -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (-not $version) { throw 'No versioned Visual C++ redistributable directory found.' }
$runtime = Get-ChildItem -Path (Join-Path $version.FullName 'x64/Microsoft.VC*.CRT') -Directory | Select-Object -First 1
if (-not $runtime -or -not (Test-Path -LiteralPath $Bundle -PathType Container)) {
    throw 'The x64 CRT or built application bundle is missing.'
}
Get-ChildItem -LiteralPath $runtime.FullName -Filter '*.dll' |
    Copy-Item -Destination $Bundle
foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Bundle $name))) {
        throw "Required redistributable runtime was not copied: $name"
    }
}
Write-Output 'Visual C++ x64 redistributable DLLs copied into the application bundle.'
