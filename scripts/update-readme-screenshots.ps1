$root = (Get-Location).Path
$shotsDir = Join-Path $root "docs\screenshots"
$readmePath = Join-Path $root "README.md"

Write-Host ""
Write-Host "=== Update README with screenshots ==="
Write-Host ""

if (-not (Test-Path -LiteralPath $shotsDir)) {
    Write-Host "docs/screenshots/ not found" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $readmePath)) {
    Write-Host "README.md not found" -ForegroundColor Red
    exit 1
}

# Find image files
$images = Get-ChildItem -Path $shotsDir -File |
    Where-Object { $_.Extension -match '^\.(png|jpg|jpeg|gif|webp)$' } |
    Sort-Object Name

if ($images.Count -eq 0) {
    Write-Host "No images found in docs/screenshots/" -ForegroundColor Yellow
    Write-Host "Put your .png screenshots there and re-run." -ForegroundColor Yellow
    exit 1
}

Write-Host ("Found " + $images.Count + " image(s):") -ForegroundColor Green
foreach ($img in $images) {
    Write-Host ("  - " + $img.Name) -ForegroundColor Cyan
}

# Build markdown block
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("## Screenshots")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("### Dashboard")
[void]$sb.AppendLine("")

$dashboard = $images | Where-Object { $_.BaseName -match 'dashboard' } | Select-Object -First 1
$airports  = $images | Where-Object { $_.BaseName -match 'airport' }   | Select-Object -First 1
$flights   = $images | Where-Object { $_.BaseName -match 'flight' }    | Select-Object -First 1
$confirmed = $images | Where-Object { $_.BaseName -match 'confirm' -or $_.BaseName -match 'success' } | Select-Object -First 1
$expired   = $images | Where-Object { $_.BaseName -match 'expire' -or $_.BaseName -match 'compensat' -or $_.BaseName -match 'fail' } | Select-Object -First 1
$bookings  = $images | Where-Object { $_.BaseName -match 'booking' -and $_.BaseName -notmatch 'confirm|expire|compensat|fail' } | Select-Object -First 1

$used = New-Object System.Collections.Generic.HashSet[string]

function Add-Section {
    param($Title, $Img, $AltText, $Caption)
    if ($null -eq $Img) { return }
    [void]$script:sb.AppendLine("### " + $Title)
    [void]$script:sb.AppendLine("")
    [void]$script:sb.AppendLine("![" + $AltText + "](docs/screenshots/" + $Img.Name + ")")
    [void]$script:sb.AppendLine("")
    if ($Caption) {
        [void]$script:sb.AppendLine("_" + $Caption + "_")
        [void]$script:sb.AppendLine("")
    }
    [void]$script:used.Add($Img.Name)
}

# If dashboard exists, use it as first section (already started above)
if ($null -ne $dashboard) {
    [void]$sb.AppendLine("![Dashboard overview](docs/screenshots/" + $dashboard.Name + ")")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("_Live counters from both bounded contexts: flights, airports, bookings, active bookings._")
    [void]$sb.AppendLine("")
    [void]$used.Add($dashboard.Name)
}

# Add remaining sections in a sensible order
Add-Section -Title "Airports" -Img $airports -AltText "Airports list" -Caption "Reference data synchronized from the external bookings database via ACL."
Add-Section -Title "Flights" -Img $flights -AltText "Flights list" -Caption "Search by route and date. Delay and Cancel actions."
Add-Section -Title "Bookings" -Img $bookings -AltText "Bookings list" -Caption "List of bookings with status and quick actions."
Add-Section -Title "Saga: confirmed" -Img $confirmed -AltText "Booking confirmed" -Caption "Green panel: verify flight, reserve seat, charge payment, confirm."
Add-Section -Title "Saga: compensated" -Img $expired -AltText "Booking expired after compensation" -Caption "Red panel: charge failed, compensation refunded payment, released seat, marked booking Expired."

# Any remaining images (not used yet)
$remaining = $images | Where-Object { -not $script:used.Contains($_.Name) }
foreach ($img in $remaining) {
    [void]$sb.AppendLine("### " + $img.BaseName)
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("![" + $img.BaseName + "](docs/screenshots/" + $img.Name + ")")
    [void]$sb.AppendLine("")
}

[void]$sb.AppendLine("---")

$newBlock = $sb.ToString()

# Replace existing Screenshots section in README
$readme = [System.IO.File]::ReadAllText($readmePath)

# Match "## Screenshots" up to the next "\n---\n" (the horizontal rule after the section)
$pattern = '(?s)## Screenshots.*?\r?\n---\r?\n'
if ($readme -match $pattern) {
    $readme = [regex]::Replace($readme, $pattern, $newBlock + "`r`n")
    Write-Host "  + replaced Screenshots section in README" -ForegroundColor Green
} else {
    Write-Host "  Screenshots section not found - check README format" -ForegroundColor Yellow
    exit 1
}

[System.IO.File]::WriteAllText($readmePath, $readme, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host ""
Write-Host "Open README.md and verify the Screenshots section." -ForegroundColor Yellow
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "docs: add UI screenshots to README"'
Write-Host "  git push"
Write-Host ""