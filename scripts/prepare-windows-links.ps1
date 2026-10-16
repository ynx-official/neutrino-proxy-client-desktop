$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$metadata = Get-Content -Raw -LiteralPath (Join-Path $projectRoot '.flutter-plugins-dependencies') | ConvertFrom-Json
$linkRoot = Join-Path $projectRoot 'windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Force -Path $linkRoot | Out-Null
foreach ($plugin in $metadata.plugins.windows) {
    $linkPath = Join-Path $linkRoot $plugin.name
    $pluginPath = [System.IO.Path]::GetFullPath($plugin.path)
    if (-not (Test-Path -LiteralPath $linkPath)) {
        New-Item -ItemType Junction -Path $linkPath -Target $pluginPath | Out-Null
    }
}
Write-Output 'Project-local plugin links are ready. No system settings changed.'
