$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'Launch.ps1'
$testDir = Join-Path ([IO.Path]::GetTempPath()) ('codex-launch-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
function Assert($condition, $label) { if (-not $condition) { throw $label } }
try {
    Copy-Item -LiteralPath $source -Destination (Join-Path $testDir 'Launch.ps1')
    Set-Content -LiteralPath (Join-Path $testDir 'StartAgent.ps1') -Value 'param([switch]$Restart); $global:launchTestState.agentStarted = $true; if ($Restart) { $global:launchTestState.agentRestarts++ }'
    Set-Content -LiteralPath (Join-Path $testDir 'SelectDebugPort.ps1') -Value 'function Select-DebugPort($PreferredPort) { if ($global:launchTestState.forcePortFallback) { 19335 } else { $PreferredPort } }'
    Set-Content -LiteralPath (Join-Path $testDir 'config.json') -Value '{"port":9335,"python":"keep-this-runtime","mode":"inline"}'
    function Get-AppxPackage { [pscustomobject]@{Version=[version]'1.0';InstallLocation=$testDir} }
    function Test-Path { param($LiteralPath) if ($LiteralPath -like '*app\ChatGPT.exe') { $true } else { Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath } }
    $global:launchTestState = @{running=$true;reachable=$false;launches=@();exitsAfterPoll=$false;polls=0;agentStarted=$false;agentRestarts=0;forcePortFallback=$false}
    function Get-Process {
        $global:launchTestState.polls++
        if ($global:launchTestState.running -and -not ($global:launchTestState.exitsAfterPoll -and $global:launchTestState.polls -gt 1)) { [pscustomobject]@{Path='C:\WindowsApps\OpenAI.Codex\app\ChatGPT.exe'} }
    }
    function Invoke-RestMethod {
        if (-not $global:launchTestState.reachable) { throw 'Connection refused' }
        @([pscustomobject]@{type='page';url='app://-/index.html'})
    }
    function Start-Process { param($FilePath, $ArgumentList, $WorkingDirectory, $WindowStyle) $global:launchTestState.launches += ,$ArgumentList; $global:launchTestState.reachable = $true }
    function Start-Sleep {}
    & (Join-Path $testDir 'Launch.ps1') -NoDialogs
    $state = Get-Content -LiteralPath (Join-Path $testDir 'launch-status.json') -Raw | ConvertFrom-Json
    Assert ($state.state -eq 'blocked_existing_process') ('Existing non-debug Codex must be recorded, got ' + ($state | ConvertTo-Json -Compress))
    Assert ($global:launchTestState.launches.Count -eq 0) 'Do not start a competing instance or stop active tasks'
    $global:launchTestState.exitsAfterPoll = $true; $global:launchTestState.polls = 0
    & (Join-Path $testDir 'Launch.ps1') -NoDialogs -WaitForExit
    $state = Get-Content -LiteralPath (Join-Path $testDir 'launch-status.json') -Raw | ConvertFrom-Json
    Assert ($global:launchTestState.launches.Count -eq 1) 'Wait for old process exit, then launch once'
    Assert ($global:launchTestState.launches[0] -contains '--remote-debugging-port=9335') 'Required debug port survives launch'
    Assert ($state.state -eq 'ready') 'Check actual endpoint after launch'
    $global:launchTestState.exitsAfterPoll = $false; $global:launchTestState.polls = 0; $global:launchTestState.running = $true
    & (Join-Path $testDir 'Launch.ps1') -NoDialogs
    Assert ($global:launchTestState.launches.Count -eq 1) 'Healthy existing Codex must not relaunch'
    Assert ($global:launchTestState.agentStarted) 'Start the collector'
    $global:launchTestState.running = $false; $global:launchTestState.reachable = $false; $global:launchTestState.forcePortFallback = $true
    & (Join-Path $testDir 'Launch.ps1') -NoDialogs
    $configAfterFallback = Get-Content -LiteralPath (Join-Path $testDir 'config.json') -Raw | ConvertFrom-Json
    Assert ($configAfterFallback.port -eq 19335) 'Occupied configured port must be replaced in shared collector config'
    Assert ($configAfterFallback.python -eq 'keep-this-runtime' -and $configAfterFallback.mode -eq 'inline') 'Port fallback preserves other plugin configuration'
    Assert ($global:launchTestState.launches[-1] -contains '--remote-debugging-port=19335') 'Codex receives the replacement port'
    Assert ($global:launchTestState.agentRestarts -ge 1) 'Collector reloads shared port before launching Codex'
    Write-Output 'PASS: existing process, wait-for-exit, occupied-port replacement, shared config preservation, collector reload, healthy reuse'
} finally {
    Assert ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($testDir)) -eq [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')) 'Cleanup stays in temp'
    Remove-Item -LiteralPath $testDir -Recurse -Force
    Remove-Variable -Name launchTestState -Scope Global
}
