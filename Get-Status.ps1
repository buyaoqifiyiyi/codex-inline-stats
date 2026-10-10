$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
$package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
$result = [ordered]@{
    pluginVersion = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
    codexVersion = [string]$package.Version
    nodeExists = (Test-Path -LiteralPath $config.node)
    pythonExists = (Test-Path -LiteralPath $config.python)
    debugPort = $config.port
    debugReachable = $false
    codexPageFound = $false
    debugAddress = $null
}
foreach ($address in @('127.0.0.1', '[::1]')) {
    try {
        $targets = Invoke-RestMethod -Uri "http://${address}:$($config.port)/json/list" -TimeoutSec 3
        $result.debugReachable = $true
        $result.debugAddress = $address
        $result.codexPageFound = [bool]($targets | Where-Object { $_.type -eq 'page' -and $_.url -like 'app://-/index.html*' })
        if ($result.codexPageFound) { break }
    } catch {}
}
$status = Join-Path $PSScriptRoot 'status.json'
if (Test-Path -LiteralPath $status) { $result.collector = Get-Content -LiteralPath $status -Raw | ConvertFrom-Json }
$launchStatus = Join-Path $PSScriptRoot 'launch-status.json'
if (Test-Path -LiteralPath $launchStatus) { $result.launch = Get-Content -LiteralPath $launchStatus -Raw | ConvertFrom-Json }
$result | ConvertTo-Json -Depth 4
