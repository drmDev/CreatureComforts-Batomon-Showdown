param(
    [string]$Root = (Get-Location).Path,
    [string]$Godot = 'C:\Code\Godot\Godot_v4.7.2-stable_win64_console.exe'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw "Godot executable not found: $Godot"
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$runner = Join-Path $Root 'tests\run_tests.gd'
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
    throw "Test runner not found: $runner"
}

& $Godot --headless --script $runner
exit $LASTEXITCODE
