# run-from-clipboard.ps1
# Reads PowerShell script from clipboard, saves to temp, executes it.
# Usage: copy script text (Ctrl+C), then run:
#   .\run-from-clipboard.ps1
# Or with an alias (see setup instructions).

param(
    [switch]$Keep,
    [switch]$NoPause
)

$raw = Get-Clipboard -Raw

if ([string]::IsNullOrWhiteSpace($raw)) {
    Write-Host "Clipboard is empty. Copy a PowerShell script first (Ctrl+C)." -ForegroundColor Red
    exit 1
}

# Sanity check: must look like a PowerShell script, not prose.
if ($raw -notmatch '\$|function |param\(|<Project|Set-|Get-|dotnet |docker ') {
    Write-Host "Clipboard content does not look like a script. First 200 chars:" -ForegroundColor Yellow
    Write-Host $raw.Substring(0, [Math]::Min(200, $raw.Length))
    Write-Host ""
    $answer = Read-Host "Run anyway? (y/N)"
    if ($answer -ne 'y') { exit 1 }
}

$tempDir = Join-Path $env:TEMP "flights-platform-scripts"
if (-not (Test-Path -LiteralPath $tempDir)) {
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$tempFile = Join-Path $tempDir "from-clipboard-$stamp.ps1"

# Write as UTF-8 without BOM
[System.IO.File]::WriteAllText($tempFile, $raw, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "=== Running: $tempFile ===" -ForegroundColor Cyan
Write-Host ""

# Execute the script in a child PowerShell so we get a clean scope
& $tempFile

$exitCode = $LASTEXITCODE

if (-not $Keep) {
    try { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue } catch {}
} else {
    Write-Host ""
    Write-Host "Script kept at: $tempFile" -ForegroundColor Yellow
}

if (-not $NoPause) {
    Write-Host ""
    Write-Host "Press any key to close..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

exit $exitCode