param(
    [string]$Root = (Get-Location).Path,
    [string]$Godot = 'C:\Code\Godot\Godot_v4.7.2-stable_win64_console.exe'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw "Godot executable not found: $Godot"
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$files = @(Get-ChildItem -LiteralPath $Root -Filter '*.gd' -File -Recurse |
    Where-Object { $_.FullName -notmatch '[\\/](\.git|\.godot|examples)[\\/]' } |
    Sort-Object FullName)

if ($files.Count -eq 0) {
    Write-Host "No .gd files found in $Root"
    exit 1
}

$failed = @()
foreach ($file in $files) {
    Write-Host "`nChecking $($file.FullName)" -ForegroundColor Cyan
    & $Godot --headless --check-only --script $file.FullName
    $checkExitCode = $LASTEXITCODE
    if ($checkExitCode -ne 0) {
        $failed += $file.FullName
        Write-Host "FAIL (exit $checkExitCode)" -ForegroundColor Red
    } else {
        Write-Host 'PASS' -ForegroundColor Green
    }
}

Write-Host "`nChecked $($files.Count) files: $($files.Count - $failed.Count) passed, $($failed.Count) failed."
if ($failed.Count -gt 0) {
    Write-Host 'Failed files:' -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" }
    exit 1
}
exit 0
