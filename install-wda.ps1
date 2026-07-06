# install-wda.ps1 — Install WebDriverAgent IPA to connected iOS device via go-ios
# Usage: .\install-wda.ps1 [-IpaPath <path>]
param(
    [string]$IpaPath = ""
)

$ErrorActionPreference = "Stop"

# ── Find IPA ──────────────────────────────────────────────────
if (-not $IpaPath) {
    $candidates = @(
        "$PSScriptRoot\wda-build-output\WebDriverAgent.ipa",
        "$PSScriptRoot\WebDriverAgent.ipa",
        "$env:USERPROFILE\Downloads\WebDriverAgent.ipa"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $IpaPath = $c
            break
        }
    }
}

if (-not $IpaPath -or -not (Test-Path $IpaPath)) {
    Write-Host @"

=== No WDA IPA found ===

To download the WDA IPA from GitHub Actions:
  Run your 'Build WebDriverAgent IPA' workflow on GitHub, then:

  gh run download -n WebDriverAgent

Or download manually from the Actions → Artifacts page.

Then re-run: .\install-wda.ps1 -IpaPath path\to\WebDriverAgent.ipa
"@
    exit 1
}

Write-Host "=== Using IPA: $IpaPath ==="

# ── Check device ────────────────────────────────────────────────
Write-Host "=== Checking connected iOS devices ==="
$devices = (& ios list 2>$null | ConvertFrom-Json)
if (-not $devices -or $devices.deviceList.Count -eq 0) {
    Write-Host "ERROR: No iOS device detected. Connect via USB and tap 'Trust' on device."
    exit 1
}

$udid = $devices.deviceList[0].udid
Write-Host "Device found: $udid"

# ── Install WDA ────────────────────────────────────────────────
Write-Host "=== Installing WebDriverAgent to device ==="
ios install --path $IpaPath
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to install WDA"
    exit 1
}
Write-Host "WDA installed successfully"

# ── iOS 17+ tunnel ──────────────────────────────────────────────
Write-Host "=== Starting tunnel (for iOS 17+) ==="
ios tunnel start
Write-Host "Tunnel started (ignore errors for iOS 16 or below)"

# ── Forward WDA port ───────────────────────────────────────────
Write-Host "=== Setting up port forwarding (8100 → device:8100) ==="
Start-Process -NoNewWindow ios -ArgumentList "forward 8100 8100"
Start-Sleep -Seconds 2

# ── Launch WDA ─────────────────────────────────────────────────
Write-Host "=== Launching WebDriverAgent on device ==="
ios runwda
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: runwda may need different bundle/testrunner IDs for your signing team"
}

# ── Verify ─────────────────────────────────────────────────────
Write-Host "=== Verify WDA is running ==="
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8100/status" -UseBasicParsing -TimeoutSec 10
    Write-Host "SUCCESS: WDA is running!"
    Write-Host $response.Content
} catch {
    Write-Host "WARNING: Could not reach WDA at http://localhost:8100/status"
    Write-Host "Check: 1) Does your device show the WDA app?"
    Write-Host "       2) Did you tap 'Trust' on the device for the developer certificate?"
    Write-Host "       3) Is the correct team ID in the provisioning profile?"
}
