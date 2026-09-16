# PowerShell 5.1 compatible - no here-string issues

$root = (Get-Location).Path

function Save-File {
    param([string]$Path, [string]$Content)
    $full = Join-Path $root $Path
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [System.IO.File]::WriteAllText($full, $Content, [System.Text.UTF8Encoding]::new($false))
    Write-Host ("  + " + $Path)
}

Write-Host ""
Write-Host "=== Fix UI step 1: button styles + header ==="
Write-Host ""

# ---------------------------------------------------------------------------
# styles.scss
# ---------------------------------------------------------------------------
$stylesLines = @(
'@import "primeicons/primeicons.css";',
'',
':root {',
'  --bg: #f8fafc;',
'  --surface: #ffffff;',
'  --border: #e2e8f0;',
'  --text: #0f172a;',
'  --text-muted: #64748b;',
'  --primary: #3b82f6;',
'  --primary-hover: #2563eb;',
'  --success: #16a34a;',
'  --success-hover: #15803d;',
'  --danger: #dc2626;',
'  --danger-hover: #b91c1c;',
'  --warning: #f59e0b;',
'  --warning-hover: #d97706;',
'}',
'',
'html.dark {',
'  --bg: #0f172a;',
'  --surface: #1e293b;',
'  --border: #334155;',
'  --text: #f1f5f9;',
'  --text-muted: #94a3b8;',
'}',
'',
'* { box-sizing: border-box; }',
'',
'html, body {',
'  margin: 0;',
'  padding: 0;',
'  height: 100%;',
'  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;',
'  background: var(--bg);',
'  color: var(--text);',
'  transition: background 0.2s, color 0.2s;',
'}',
'',
'a { color: var(--primary); text-decoration: none; }',
'',
'.page-header {',
'  display: flex;',
'  align-items: center;',
'  justify-content: space-between;',
'  margin-bottom: 1.5rem;',
'  gap: 1rem;',
'  flex-wrap: wrap;',
'}',
'.page-header h1 { margin: 0 0 0.25rem; font-size: 1.5rem; }',
'.page-header .subtitle { color: var(--text-muted); margin: 0; }',
'.page-header .actions { display: flex; gap: 0.5rem; align-items: center; }',
'',
'/* Buttons */',
'.btn {',
'  display: inline-flex;',
'  align-items: center;',
'  justify-content: center;',
'  gap: 0.5rem;',
'  padding: 0.55rem 1rem;',
'  border-radius: 6px;',
'  font-size: 0.95rem;',
'  font-weight: 500;',
'  border: 1px solid transparent;',
'  cursor: pointer;',
'  transition: background 0.15s, opacity 0.15s;',
'  white-space: nowrap;',
'  font-family: inherit;',
'  line-height: 1.1;',
'  text-decoration: none;',
'}',
'.btn i { font-size: 0.95rem; }',
'.btn:disabled { opacity: 0.5; cursor: not-allowed; }',
'',
'.btn-primary { background: var(--primary); color: #ffffff; }',
'.btn-primary:hover:not(:disabled) { background: var(--primary-hover); }',
'',
'.btn-success { background: var(--success); color: #ffffff; }',
'.btn-success:hover:not(:disabled) { background: var(--success-hover); }',
'',
'.btn-danger { background: var(--danger); color: #ffffff; }',
'.btn-danger:hover:not(:disabled) { background: var(--danger-hover); }',
'',
'.btn-warn { background: var(--warning); color: #ffffff; }',
'.btn-warn:hover:not(:disabled) { background: var(--warning-hover); }',
'',
'.btn-secondary {',
'  background: transparent;',
'  color: var(--text);',
'  border-color: var(--border);',
'}',
'.btn-secondary:hover:not(:disabled) { background: var(--bg); }',
'',
'.btn-sm {',
'  padding: 0.35rem 0.75rem;',
'  font-size: 0.85rem;',
'}',
'.btn-sm i { font-size: 0.85rem; }'
)

$stylesContent = $stylesLines -join "`r`n"
Save-File "frontend/src/styles.scss" $stylesContent

# ---------------------------------------------------------------------------
# header.component.ts
# ---------------------------------------------------------------------------
$headerLines = @(
"import { Component, inject, OnInit, OnDestroy } from '@angular/core';",
"import { HealthService } from '../services/health.service';",
"import { ThemeService } from '../services/theme.service';",
"",
"@Component({",
"  selector: 'app-header',",
"  standalone: true,",
"  imports: [],",
"  template: `",
"    <header class=""header"">",
"      <div class=""health"" [class.online]=""health.isOnline()"" [class.offline]=""!health.isOnline()"">",
"        <span class=""dot""></span>",
"        <span>{{ health.isOnline() ? 'API online' : 'API offline' }}</span>",
"      </div>",
"",
"      <button class=""btn btn-secondary"" type=""button"" (click)=""theme.toggle()"">",
"        <i class=""pi"" [class.pi-sun]=""theme.isDark()"" [class.pi-moon]=""!theme.isDark()""></i>",
"        <span>{{ theme.isDark() ? 'Light theme' : 'Dark theme' }}</span>",
"      </button>",
"    </header>",
"  `,",
"  styles: [`",
"    .header {",
"      display: flex;",
"      align-items: center;",
"      justify-content: space-between;",
"      padding: 0.75rem 2rem;",
"      background: var(--surface);",
"      border-bottom: 1px solid var(--border);",
"    }",
"    .health {",
"      display: flex;",
"      align-items: center;",
"      gap: 0.5rem;",
"      font-size: 0.9rem;",
"      color: var(--text-muted);",
"    }",
"    .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--text-muted); }",
"    .health.online .dot { background: var(--success); }",
"    .health.online span:last-child { color: var(--success); }",
"    .health.offline .dot { background: var(--danger); }",
"    .health.offline span:last-child { color: var(--danger); }",
"  `]",
"})",
"export class HeaderComponent implements OnInit, OnDestroy {",
"  readonly health = inject(HealthService);",
"  readonly theme = inject(ThemeService);",
"",
"  ngOnInit(): void { this.health.start(); }",
"  ngOnDestroy(): void { this.health.stop(); }",
"}"
)

$headerContent = $headerLines -join "`r`n"
Save-File "frontend/src/app/core/layout/header.component.ts" $headerContent

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Build frontend ==="

Push-Location (Join-Path $root "frontend")
try {
    cmd /c "npm run build 2>&1"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FRONTEND BUILD FAILED" -ForegroundColor Red
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
Write-Host "Check header: should show ""Dark theme"" / ""Light theme"" text next to icon." -ForegroundColor Yellow
Write-Host ""