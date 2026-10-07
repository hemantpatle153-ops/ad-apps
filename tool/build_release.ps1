<#
Builds the Google Play upload bundles (.aab) on the Windows laptop.

  powershell -ExecutionPolicy Bypass -File tool\build_release.ps1                 # all apps
  powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 qr_scanner      # one app

Reads two things that never go in git, from the signing folder
(default: %USERPROFILE%\Downloads\APPS\signing):
  <app>-upload.jks + <app>.key.properties   the upload key of each app
  admob.json (optional)                      real AdMob IDs, see admob.example.json;
                                             an app without an entry ships with ads off

Bundles land in %USERPROFILE%\Downloads\APPS\play_release\<store name>-<version>.aab.
#>
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Apps,
    [string]$Signing = "$env:USERPROFILE\Downloads\APPS\signing",
    [string]$Out = "$env:USERPROFILE\Downloads\APPS\play_release"
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# Folder name -> name used for the output file.
$storeNames = [ordered]@{
    qr_scanner      = 'qr_scanner'
    daily_sudoku    = 'daily_sudoku'
    doc_scanner     = 'doc_scanner'
    expense_tracker = 'expense_tracker'
    water_habit     = 'water_habit'
    multi_speaker   = 'multi_speaker'
    video_player    = 'video_player'
    snakes_ladders  = 'dice_dhamaal'
}
if (-not $Apps) { $Apps = @($storeNames.Keys) }

$admobFile = Join-Path $Signing 'admob.json'
$admob = if (Test-Path $admobFile) { Get-Content $admobFile -Raw | ConvertFrom-Json } else { $null }
New-Item -ItemType Directory -Force $Out | Out-Null

foreach ($app in $Apps) {
    if (-not $storeNames.Contains($app)) { throw "Unknown app '$app'. Use one of: $($storeNames.Keys -join ', ')" }
    Write-Host "`n=== $app" -ForegroundColor Cyan
    $dir = Join-Path $root "apps\$app"

    # Upload key: write android\key.properties (git-ignored) pointing at the keystore.
    $jks = Join-Path $Signing "$app-upload.jks"
    $props = Join-Path $Signing "$app.key.properties"
    if (-not (Test-Path $jks) -or -not (Test-Path $props)) {
        throw "No upload key for $app. Create it once (and back it up; it can't be replaced):`n" +
            "  keytool -genkey -v -keystore `"$jks`" -keyalg RSA -keysize 2048 -validity 10000 -alias upload`n" +
            "then save storePassword, keyAlias and keyPassword in $props"
    }
    $keep = Get-Content $props | Where-Object { $_ -match '^(storePassword|keyAlias|keyPassword)=' }
    $lines = @("storeFile=$($jks -replace '\\', '/')") + $keep
    Set-Content -Path (Join-Path $dir 'android\key.properties') -Value $lines -Encoding ascii

    $ids = if ($admob) { $admob.$app } else { $null }
    $buildArgs = @('build', 'appbundle', '--release')
    if (-not $ids) {
        Write-Host "No AdMob IDs for $app in admob.json: building with ads off." -ForegroundColor Yellow
        $buildArgs += '--dart-define=ADS=off'
    } else {
        if (-not $ids.appId -or -not $ids.banner -or -not $ids.interstitial) {
            throw "admob.json entry for '$app' needs appId, banner and interstitial."
        }
        $buildArgs += "-PadmobAppId=$($ids.appId)",
            "--dart-define=ADMOB_BANNER_ID=$($ids.banner)",
            "--dart-define=ADMOB_INTERSTITIAL_ID=$($ids.interstitial)"
        if ($ids.rewarded) { $buildArgs += "--dart-define=ADMOB_REWARDED_ID=$($ids.rewarded)" }
    }

    Push-Location $dir
    try {
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed for $app" }
        flutter @buildArgs
        if ($LASTEXITCODE -ne 0) { throw "flutter build appbundle failed for $app" }
    } finally { Pop-Location }

    $version = ((Select-String -Path (Join-Path $dir 'pubspec.yaml') -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value) -replace '\+', '-'
    $aab = Join-Path $Out "$($storeNames[$app])-$version.aab"
    Copy-Item (Join-Path $dir 'build\app\outputs\bundle\release\app-release.aab') $aab -Force
    Write-Host "Saved $aab" -ForegroundColor Green
}
