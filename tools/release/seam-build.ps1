# SPDX-FileCopyrightText: 2026 Grayson Adams
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Release build of Seam for Android, signed with a key that comes in through
# the environment and is never written anywhere but a temporary folder, which
# is removed when the build ends.
#
#   -Mode bundle   Play bundle (.aab), signed with the upload key.
#                  Environment: SEAM_KS_B64 = UPLOAD_KEYSTORE_B64,
#                               SEAM_KS_PASSWORD = UPLOAD_KEYSTORE_PASSWORD.
#   -Mode phone    arm64 APK, signed with the app signing key, so it installs
#                  over the Play build of dev.threeonetwo.seam.
#                  Environment: SEAM_KS_B64 = APP_SIGNING_KEYSTORE_B64,
#                               SEAM_KS_PASSWORD = APP_SIGNING_KEYSTORE_PASSWORD.
#
# Both keys are in op://Production/seam-signing; tools/release/README.md has
# the sandbroker call that passes them in. -VersionCode is Seam's one
# versionCode counter and must be higher than any build already uploaded or
# installed.
#
# Both modes are the Play build, so they link Firebase Cloud Messaging for
# the duration of the build (play-fcm.ps1) and send pushes through
# -PushGateway. That needs SEAM_GOOGLE_SERVICES_JSON, the contents of
# op://Production/seam-push/GOOGLE_SERVICES_JSON. -NoFcm builds without FCM
# or a gateway, as F-Droid does.
param(
    [Parameter(Mandatory = $true)][ValidateSet('bundle', 'phone')][string]$Mode,
    [Parameter(Mandatory = $true)][ValidateRange(3582, 2100000000)][int]$VersionCode,
    [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$Flutter = 'C:\src\flutter\bin\flutter.bat',
    [string]$Log = (Join-Path $env:TEMP 'seam-build.log'),
    # Empty takes $PlayPushGateway from play-fcm.ps1.
    [string]$PushGateway = '',
    [switch]$NoFcm
)

. (Join-Path $PSScriptRoot 'play-fcm.ps1')
if (-not $PushGateway) { $PushGateway = $PlayPushGateway }
$fcmBackup = $null

$d = Join-Path $env:TEMP ('seam-ks-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
"start $(Get-Date -Format o) mode $Mode versionCode $VersionCode fcm $(-not $NoFcm) repo $Repo keydir $d" |
    Out-File -Append -Encoding ascii $Log
$rc = 1
try {
    if (-not $env:SEAM_KS_B64 -or -not $env:SEAM_KS_PASSWORD) {
        throw 'SEAM_KS_B64 and SEAM_KS_PASSWORD must be set (see tools/release/README.md)'
    }
    if (-not $NoFcm -and -not $env:SEAM_GOOGLE_SERVICES_JSON) {
        throw 'SEAM_GOOGLE_SERVICES_JSON must be set, or pass -NoFcm (see tools/release/README.md)'
    }
    New-Item -ItemType Directory $d | Out-Null
    $ks = Join-Path $d 'key.keystore'
    [IO.File]::WriteAllBytes($ks, [Convert]::FromBase64String($env:SEAM_KS_B64))
    $password = $env:SEAM_KS_PASSWORD
    $env:SEAM_KS_B64 = $null
    $env:SEAM_KS_PASSWORD = $null
    # build.gradle.kts refuses a build that has both keys, so clear the other.
    if ($Mode -eq 'bundle') {
        $env:SEAM_APP_SIGNING_KEYSTORE = $null
        $env:SEAM_APP_SIGNING_PASSWORD = $null
        $env:SEAM_UPLOAD_STORE_FILE = $ks
        $env:SEAM_UPLOAD_STORE_PASSWORD = $password
        $env:SEAM_UPLOAD_KEY_PASSWORD = $password
        $env:SEAM_UPLOAD_KEY_ALIAS = 'upload'
        $build = @('build', 'appbundle', '--release', "--build-number=$VersionCode")
    } else {
        foreach ($v in 'STORE_FILE', 'STORE_PASSWORD', 'KEY_ALIAS', 'KEY_PASSWORD') {
            Remove-Item "env:SEAM_UPLOAD_$v" -ErrorAction SilentlyContinue
        }
        $env:SEAM_APP_SIGNING_KEYSTORE = $ks
        $env:SEAM_APP_SIGNING_PASSWORD = $password
        $build = @('build', 'apk', '--release', '--target-platform', 'android-arm64',
            "--build-number=$VersionCode")
    }
    $password = $null
    if (-not $NoFcm) {
        $fcmBackup = Enable-PlayFcm -Repo $Repo -Flutter $Flutter `
            -GoogleServicesJson $env:SEAM_GOOGLE_SERVICES_JSON -Log $Log
        $build += "--dart-define=SEAM_PUSH_GATEWAY_URL=$PushGateway"
    }
    $env:SEAM_GOOGLE_SERVICES_JSON = $null
    Set-Location $Repo
    & $Flutter @build 2>&1 | Out-File -Append -Encoding ascii $Log
    $rc = $LASTEXITCODE
    "flutter rc=$rc" | Out-File -Append -Encoding ascii $Log
} catch {
    "error: $($_.Exception.Message)" | Out-File -Append -Encoding ascii $Log
} finally {
    if (-not $NoFcm) {
        Disable-PlayFcm -Repo $Repo -Backup $fcmBackup -Log $Log
    }
    foreach ($v in 'SEAM_APP_SIGNING_KEYSTORE', 'SEAM_APP_SIGNING_PASSWORD',
        'SEAM_UPLOAD_STORE_FILE', 'SEAM_UPLOAD_STORE_PASSWORD', 'SEAM_UPLOAD_KEY_ALIAS',
        'SEAM_UPLOAD_KEY_PASSWORD', 'SEAM_GOOGLE_SERVICES_JSON') {
        Remove-Item "env:$v" -ErrorAction SilentlyContinue
    }
    Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue
    $msg = if (Test-Path $d) { "keydir STILL PRESENT $d" } else { "keydir removed $d" }
    $msg | Out-File -Append -Encoding ascii $Log
    "DONE $(Get-Date -Format o)" | Out-File -Append -Encoding ascii $Log
}
exit $rc
