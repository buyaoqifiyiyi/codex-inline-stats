$ErrorActionPreference = 'Stop'
$package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
if (-not $package) { throw 'Codex MSIX installation was not found.' }
$executable = Join-Path $package.InstallLocation 'app\ChatGPT.exe'
if (-not (Test-Path -LiteralPath $executable)) { throw 'Unsupported Codex installation layout.' }
& (Join-Path $PSScriptRoot 'StartAgent.ps1')
$running = Get-Process -Name ChatGPT -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*OpenAI.Codex*' }
if ($running) { Write-Output 'Codex is already running. Fully quit it first if statistics are missing.'; return }
$config = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
Start-Process -FilePath $executable -ArgumentList @("--remote-debugging-port=$($config.port)", '--remote-debugging-address=127.0.0.1') -WorkingDirectory (Split-Path -Parent $executable) -WindowStyle Normal
