[CmdletBinding()]
param([switch]$WaitForExit, [switch]$NoDialogs)
$ErrorActionPreference = 'Stop'
function Write-LaunchStatus($state, $detail = '') {
    @{state=$state;detail=$detail;updatedAt=[DateTime]::UtcNow.ToString('o')} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'launch-status.json') -Encoding UTF8
}
function Show-LaunchMessage($message, [switch]$Cancelable) {
    if ($NoDialogs) { Write-Output $message; return $false }
    Add-Type -AssemblyName System.Windows.Forms
    $buttons = if ($Cancelable) { 'OKCancel' } else { 'OK' }
    $result = [System.Windows.Forms.MessageBox]::Show($message, 'Codex（内置统计）', $buttons, 'Information')
    return $result -eq 'OK'
}
function Get-RunningCodex {
    Get-Process -Name ChatGPT -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*OpenAI.Codex*' }
}
function Test-DebugPage {
    foreach ($address in @('127.0.0.1', '[::1]')) {
        try {
            $targets = Invoke-RestMethod -Uri "http://${address}:$($config.port)/json/list" -TimeoutSec 1
            if ($targets | Where-Object { $_.type -eq 'page' -and $_.url -like 'app://-/index.html*' }) { return $true }
        } catch {}
    }
    return $false
}
$hash = [Security.Cryptography.SHA256]::Create()
$key = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($PSScriptRoot.ToLowerInvariant()))).Replace('-', '')
$hash.Dispose()
$mutex = New-Object Threading.Mutex($false, ('Local\CodexInlineStatsLaunch-' + $key))
$locked = $false
try {
    try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) {
        $null = Show-LaunchMessage '统计启动器已经在运行。如果它正在等待旧进程结束，请从菜单完全退出 Codex，启动器会自动重新打开。'
        return
    }
    Write-LaunchStatus 'checking'
    $config = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
    $package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $package) { throw 'Codex MSIX installation was not found.' }
    $executable = Join-Path $package.InstallLocation 'app\ChatGPT.exe'
    if (-not (Test-Path -LiteralPath $executable)) { throw 'Unsupported Codex installation layout.' }
    # Maintain shortcut repair only for installations that already opted into it.
    if ((Test-Path -LiteralPath (Join-Path $PSScriptRoot 'shortcut-backups.json')) -and
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'RepairShortcuts.ps1'))) {
        & (Join-Path $PSScriptRoot 'RepairShortcuts.ps1') | Out-Null
    }
    & (Join-Path $PSScriptRoot 'StartAgent.ps1')
    if (Get-RunningCodex) {
        if (Test-DebugPage) { Write-LaunchStatus 'ready'; return }
        Write-LaunchStatus 'blocked_existing_process' 'Codex is already running without a reachable debug page.'
        if (-not $WaitForExit) {
            if ($NoDialogs) { return }
            $WaitForExit = Show-LaunchMessage "Codex 已经在运行，但统计连接未启用。再次点击快捷方式不能给旧进程补加参数。`r`n`r`n点击确定后，启动器会等待 10 分钟：请先完成其他任务，再从菜单完全退出 Codex（不只是关闭窗口）。退出后将自动重新打开并启用统计。`r`n`r`n点击取消保持当前状态。" -Cancelable
            if (-not $WaitForExit) { return }
        }
        Write-LaunchStatus 'waiting_for_exit'
        $deadline = [DateTime]::UtcNow.AddMinutes(10)
        while (Get-RunningCodex) {
            if ([DateTime]::UtcNow -ge $deadline) {
                Write-LaunchStatus 'exit_timeout'
                $null = Show-LaunchMessage '等待退出已超时。请在任务结束后完全退出 Codex，再点击统计入口。'
                return
            }
            Start-Sleep -Milliseconds 500
        }
    }
    . (Join-Path $PSScriptRoot 'SelectDebugPort.ps1')
    $config = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
    $previousPort = [int]$config.port
    $selectedPort = Select-DebugPort $previousPort
    if ($selectedPort -ne $previousPort) {
        $config.port = $selectedPort
        $configPath = Join-Path $PSScriptRoot 'config.json'
        $temporaryConfig = Join-Path $PSScriptRoot ('config-' + [guid]::NewGuid().ToString('N') + '.tmp')
        $previousConfig = $temporaryConfig + '.bak'
        try {
            $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temporaryConfig -Encoding UTF8
            [IO.File]::Replace($temporaryConfig, $configPath, $previousConfig)
        } finally {
            if (Test-Path -LiteralPath $temporaryConfig) { Remove-Item -LiteralPath $temporaryConfig }
            if (Test-Path -LiteralPath $previousConfig) { Remove-Item -LiteralPath $previousConfig }
        }
    }
    # Reload configuration even if it changed while this launcher waited for exit.
    & (Join-Path $PSScriptRoot 'StartAgent.ps1') -Restart
    Write-LaunchStatus 'starting' "Debug port $selectedPort (previous $previousPort)."
    Start-Process -FilePath $executable -ArgumentList @("--remote-debugging-port=$($config.port)", '--remote-debugging-address=127.0.0.1') -WorkingDirectory (Split-Path -Parent $executable) -WindowStyle Normal
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        if (Test-DebugPage) { Write-LaunchStatus 'ready'; return }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    Write-LaunchStatus 'debug_unavailable' "Codex launched on port $selectedPort, but no debug page became reachable within 30 seconds."
    $null = Show-LaunchMessage 'Codex 已启动，但统计连接没有就绪。请运行 Get-Status.ps1 查看 launch 和 collector 状态；不要反复重启。'
} catch {
    Write-LaunchStatus 'error' $_.Exception.GetType().Name
    $null = Show-LaunchMessage '统计启动失败。请运行安装目录的 Get-Status.ps1 查看启动状态。'
    throw
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
