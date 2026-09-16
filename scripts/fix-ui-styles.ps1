$root = (Get-Location).Path
$stylesPath = Join-Path $root "frontend\src\styles.scss"

if (-not (Test-Path -LiteralPath $stylesPath)) {
    Write-Host "styles.scss not found" -ForegroundColor Red
    exit 1
}

$current = [System.IO.File]::ReadAllText($stylesPath)

if ($current -match '\.btn-primary') {
    Write-Host "  .btn styles already present - skipping" -ForegroundColor Yellow
} else {
    $btnBlock = @'

/* Buttons */
.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  padding: 0.55rem 1rem;
  border-radius: 6px;
  font-size: 0.95rem;
  font-weight: 500;
  border: 1px solid transparent;
  cursor: pointer;
  transition: background 0.15s, opacity 0.15s;
  white-space: nowrap;
  font-family: inherit;
  line-height: 1.1;
  text-decoration: none;
}
.btn i { font-size: 0.95rem; }
.btn:disabled { opacity: 0.5; cursor: not-allowed; }

.btn-primary { background: #3b82f6; color: #ffffff; }
.btn-primary:hover:not(:disabled) { background: #2563eb; }

.btn-success { background: #16a34a; color: #ffffff; }
.btn-success:hover:not(:disabled) { background: #15803d; }

.btn-danger { background: #dc2626; color: #ffffff; }
.btn-danger:hover:not(:disabled) { background: #b91c1c; }

.btn-warn { background: #f59e0b; color: #ffffff; }
.btn-warn:hover:not(:disabled) { background: #d97706; }

.btn-secondary {
  background: transparent;
  color: var(--text);
  border-color: var(--border);
}
.btn-secondary:hover:not(:disabled) { background: var(--bg); }

.btn-sm {
  padding: 0.35rem 0.75rem;
  font-size: 0.85rem;
}
.btn-sm i { font-size: 0.85rem; }
'@

    $updated = $current + $btnBlock
    [System.IO.File]::WriteAllText($stylesPath, $updated, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  + appended .btn styles to styles.scss" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Build ==="

Push-Location (Join-Path $root "frontend")
try {
    cmd /c "npm run build 2>&1"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "BUILD FAILED" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Write-Host "  + build ok" -ForegroundColor Green
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "DONE. Restart frontend:" -ForegroundColor Green
Write-Host "  cd frontend; npm start"
Write-Host ""