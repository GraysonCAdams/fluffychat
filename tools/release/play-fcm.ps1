# SPDX-FileCopyrightText: 2026 Grayson Adams
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Links Firebase Cloud Messaging into a Seam build for Google Play, and takes
# it out again. The tree in git stays free of Google code, as the F-Droid
# build needs: FCM is in it only between Enable-PlayFcm and Disable-PlayFcm.
#
# Enable-PlayFcm does what scripts/add-firebase-messaging.sh does, from
# PowerShell: it adds fcm_shared_isolate to pubspec.yaml and pubspec.lock,
# uncomments the //<GOOGLE_SERVICES> lines in lib/utils/background_push.dart
# and the FcmPushService class, and writes android/app/google-services.json,
# which turns on the google-services Gradle plugin. Disable-PlayFcm puts the
# four edited files back from their copies and deletes google-services.json.
#
#   . tools/release/play-fcm.ps1
#   $backup = Enable-PlayFcm -Repo $repo -Flutter $flutter -GoogleServicesJson $json
#   try { flutter build ... --dart-define=SEAM_PUSH_GATEWAY_URL=$PlayPushGateway }
#   finally { Disable-PlayFcm -Repo $repo -Backup $backup }

# The Matrix push gateway that relays Seam's pushes to FCM (and to APNs for
# the iOS app). Builds pass it as --dart-define=SEAM_PUSH_GATEWAY_URL.
$PlayPushGateway = 'https://seam-push.312.dev/_matrix/push/v1/notify'

$PlayFcmPackage = 'fcm_shared_isolate:4.0.0'

$PlayFcmFiles = @(
    'pubspec.yaml',
    'pubspec.lock',
    'lib\utils\background_push.dart',
    'android\app\src\main\kotlin\chat\fluffy\fluffychat\FcmPushService.kt'
)

function Enable-PlayFcm {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Flutter,
        # The contents of google-services.json for the seam-312dev Firebase
        # project (op://Production/seam-push/GOOGLE_SERVICES_JSON).
        [Parameter(Mandatory = $true)][string]$GoogleServicesJson,
        [string]$Log = (Join-Path $env:TEMP 'seam-build.log')
    )
    $backup = Join-Path $env:TEMP ('seam-fcm-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory $backup | Out-Null
    foreach ($f in $PlayFcmFiles) {
        $copy = Join-Path $backup $f
        New-Item -ItemType Directory -Force (Split-Path $copy) | Out-Null
        Copy-Item (Join-Path $Repo $f) $copy
    }
    try {
        $json = Join-Path $Repo 'android\app\google-services.json'
        [IO.File]::WriteAllText($json, $GoogleServicesJson)

        Push-Location $Repo
        try {
            & $Flutter pub add $PlayFcmPackage 2>&1 | Out-File -Append -Encoding ascii $Log
            if ($LASTEXITCODE -ne 0) { throw "flutter pub add $PlayFcmPackage failed" }
        } finally {
            Pop-Location
        }

        $dart = Join-Path $Repo 'lib\utils\background_push.dart'
        $text = [IO.File]::ReadAllText($dart)
        if (-not $text.Contains('//<GOOGLE_SERVICES>')) { throw "no //<GOOGLE_SERVICES> lines in $dart" }
        [IO.File]::WriteAllText($dart, $text.Replace('//<GOOGLE_SERVICES>', ''))

        # The class is one block comment: /* on the first line, */ on the last.
        $kotlin = Join-Path $Repo $PlayFcmFiles[3]
        $text = [IO.File]::ReadAllText($kotlin)
        $text = [regex]::Replace($text, '(?m)^/\*', '')
        $text = [regex]::Replace($text, '(?m)\*/(?=\r?$)', '')
        [IO.File]::WriteAllText($kotlin, $text)
    } catch {
        # A half-done change must not stay in the tree.
        Disable-PlayFcm -Repo $Repo -Backup $backup -Log $Log
        throw
    }

    "FCM linked, originals in $backup" | Out-File -Append -Encoding ascii $Log
    return $backup
}

function Disable-PlayFcm {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [string]$Backup,
        [string]$Log = (Join-Path $env:TEMP 'seam-build.log')
    )
    Remove-Item -Force (Join-Path $Repo 'android\app\google-services.json') -ErrorAction SilentlyContinue
    if (-not $Backup -or -not (Test-Path $Backup)) { return }
    foreach ($f in $PlayFcmFiles) {
        Copy-Item -Force (Join-Path $Backup $f) (Join-Path $Repo $f)
    }
    Remove-Item -Recurse -Force $Backup
    "FCM taken out again" | Out-File -Append -Encoding ascii $Log
}
