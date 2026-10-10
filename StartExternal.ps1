$ErrorActionPreference = 'Stop'
try {
    $config = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
    & $config.python -I -c 'import tkinter,sqlite3' 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Python with tkinter and sqlite3 is required for the external window.' }
    $pythonw = Join-Path (Split-Path $config.python -Parent) 'pythonw.exe'
    if (-not (Test-Path -LiteralPath $pythonw)) { $pythonw = $config.python }
    Start-Process -FilePath $pythonw -ArgumentList @('-I', ('"' + (Join-Path $PSScriptRoot 'external.py') + '"')) -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    $null = [System.Windows.Forms.MessageBox]::Show('外置统计启动失败，请检查安装时指定的 Python 是否包含 tkinter。', 'Codex 外置统计', 'OK', 'Error')
    throw
}
