[CmdletBinding()]
param([switch]$Restore)
$ErrorActionPreference = 'Stop'
$shell = New-Object -ComObject WScript.Shell
$receipt = Join-Path $PSScriptRoot 'shortcut-backups.json'
$entries = @()
if (Test-Path -LiteralPath $receipt) { $entries = @(Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json | ForEach-Object { $_ }) }
$launcher = Join-Path $PSScriptRoot 'Launch.ps1'
if ($Restore) {
    foreach ($entry in $entries) {
        if ((Test-Path -LiteralPath $entry.path) -and (Test-Path -LiteralPath $entry.backup)) {
            $link = $shell.CreateShortcut($entry.path)
            if ($link.Arguments.Contains($launcher)) {
                Copy-Item -LiteralPath $entry.backup -Destination $entry.path -Force
            }
        }
    }
    Write-Output 'Restored matching original Codex shortcuts; backups retained.'
    return
}
$package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
if (-not $package) { throw 'Codex installation not found.' }
$executable = Join-Path $package.InstallLocation 'app\ChatGPT.exe'
$packageDirectory = Split-Path $package.InstallLocation -Leaf
$publisher = ($packageDirectory -split '__')[-1]
$packageParent = Split-Path $package.InstallLocation -Parent
$oldExecutablePattern = '^' + [regex]::Escape($packageParent) + '\\OpenAI\.Codex_[^\\]+__' + [regex]::Escape($publisher) + '\\app\\ChatGPT\.exe$'
$iconPath = Join-Path $PSScriptRoot 'codex.ico'
$iconLocation = $(if (Test-Path -LiteralPath $iconPath) { $iconPath + ',0' } else { $executable + ',0' })
$locations = @(
    [Environment]::GetFolderPath('Desktop'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
    (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')
)
foreach ($location in $locations) {
    if (-not (Test-Path -LiteralPath $location)) { continue }
    foreach ($file in (Get-ChildItem -LiteralPath $location -Filter '*.lnk' -Recurse)) {
        $link = $shell.CreateShortcut($file.FullName)
        if ($link.Arguments.Contains($launcher)) {
            $link.IconLocation = $iconLocation
            $link.Save()
            continue
        }
        # Shell can retain the previous MSIX version's link for the same AppUserModelID.
        if ($link.TargetPath -ne $executable -and $link.TargetPath -notmatch $oldExecutablePattern) { continue }
        if (-not ($entries | Where-Object { $_.path -eq $file.FullName })) {
            $backupDir = Join-Path $PSScriptRoot 'shortcut-backups'
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            $backup = Join-Path $backupDir ([guid]::NewGuid().ToString('N') + '.lnk')
            Copy-Item -LiteralPath $file.FullName -Destination $backup
            $entries += [pscustomobject]@{path=$file.FullName;backup=$backup}
            ConvertTo-Json -InputObject @($entries) | Set-Content -LiteralPath $receipt -Encoding UTF8
        }
        $link.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $link.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $launcher + '"'
        $link.WorkingDirectory = $PSScriptRoot
        $link.IconLocation = $iconLocation
        $link.Save()
        Write-Output ('Statistics launcher applied to ' + $file.FullName)
    }
}
