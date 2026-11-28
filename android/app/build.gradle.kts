import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") // For flutter_local_notifications // Workaround for: https://github.com/MaikuB/flutter_local_notifications/issues/2286
    implementation("androidx.core:core-ktx:1.17.0") // For Android Auto
    implementation("androidx.car.app:app:1.7.0") // Android Auto conversation list
}


// Workaround for https://pub.dev/packages/unifiedpush#the-build-fails-because-of-duplicate-classes
configurations.all {
    // Use the latest version published: https://central.sonatype.com/artifact/com.google.crypto.tink/tink-android
    val tink = "com.google.crypto.tink:tink-android:1.23.0"
    // You can also use the library declaration catalog
    // val tink = libs.google.tink
    resolutionStrategy {
        force(tink)
        dependencySubstitution {
            substitute(module("com.google.crypto.tink:tink")).using(module(tink))
        }
    }
}


// flutter_shortcuts_new pulls in core-google-shortcuts, which hands every
// conversation shortcut (chat name and picture) to Google's on-device
// indexing for Assistant. Nothing here calls it: dynamic, pinned and share
// shortcuts and bubbles all go through androidx.core's ShortcutManagerCompat,
// which only notifies the library if it is present. The Play build leaves it
// out; debug and profile builds keep it.
configurations.matching { it.name.contains("release", ignoreCase = true) }.configureEach {
    exclude(group = "androidx.core", module = "core-google-shortcuts")
}

// Release builds are signed with one of Seam's two keys, neither of which
// ever enters the repo:
// - The Play upload key signs bundles for Play. Its path and passwords come
//   from android/key.properties (gitignored, like every *.jks and
//   *.keystore) or, for any value that file does not set, from SEAM_UPLOAD_*
//   environment variables. A storeFile path is resolved against android/app.
// - The app signing key, the one Play signs the installed APKs with, signs
//   release APKs that install over the Play build on a phone. It comes from
//   SEAM_APP_SIGNING_KEYSTORE (a PKCS12 file, key alias seam) and
//   SEAM_APP_SIGNING_PASSWORD.
// tools/release/README.md has the build loop; android/store/STORE-LAUNCH.md
// covers creating the upload key.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
fun uploadKeyValue(property: String, env: String): String? =
    keystoreProperties.getProperty(property) ?: System.getenv(env)
val uploadStoreFile = uploadKeyValue("storeFile", "SEAM_UPLOAD_STORE_FILE")
val appSigningStoreFile = System.getenv("SEAM_APP_SIGNING_KEYSTORE")
val appSigningPassword = System.getenv("SEAM_APP_SIGNING_PASSWORD")

android {
    namespace = "chat.fluffy.fluffychat"
    // Workaround for https://github.com/juliansteenbakker/flutter_secure_storage/issues/1224
    compileSdk = 37 //flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    signingConfigs {
        if (appSigningStoreFile != null) {
            create("release") {
                storeFile = file(appSigningStoreFile)
                storeType = "pkcs12"
                storePassword = appSigningPassword
                keyAlias = "seam"
                keyPassword = appSigningPassword
            }
        } else if (uploadStoreFile != null) {
            create("release") {
                storeFile = file(uploadStoreFile)
                storePassword = uploadKeyValue("storePassword", "SEAM_UPLOAD_STORE_PASSWORD")
                keyAlias = uploadKeyValue("keyAlias", "SEAM_UPLOAD_KEY_ALIAS")
                keyPassword = uploadKeyValue("keyPassword", "SEAM_UPLOAD_KEY_PASSWORD")
            }
        }
    }

    defaultConfig {
        // The published app. Debug and profile builds take another id in the
        // androidComponents block below.
        applicationId = "dev.threeonetwo.seam"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "Seam"
        // URL schemes for deep links and the SSO redirect. They must match
        // AppConfig.appOpenUrlScheme and appSsoUrlScheme in Dart, which pick
        // the same values by build mode. The SSO scheme starts with the
        // client_uri host, seam.312.dev, in reverse, as OIDC requires.
        manifestPlaceholders["appUrlScheme"] = "dev.threeonetwo.seam"
        manifestPlaceholders["appSsoUrlScheme"] = "dev.312.seam.auth"
        ndk { // Workaround for https://github.com/flutter/flutter/issues/162153#issuecomment-2612443642
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64", "x86")
        }
    }

    buildTypes {
        // Debug and profile builds keep the deep link scheme of the owner's
        // long-lived install, which was set up under it, and take an SSO
        // scheme of their own, so they and the release app on one device do
        // not both claim the redirect.
        debug {
            manifestPlaceholders["appUrlScheme"] = "im.fluffychat"
            manifestPlaceholders["appSsoUrlScheme"] = "dev.312.seam.dev.auth"
        }
        // Flutter's profile build type is copied from debug before the block
        // above applies, so it needs the same values set again.
        getByName("profile") {
            manifestPlaceholders["appUrlScheme"] = "im.fluffychat"
            manifestPlaceholders["appSsoUrlScheme"] = "dev.312.seam.dev.auth"
        }
        release {
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }
}

// Debug and profile builds install as chat.fluffy.fluffychat.fork, the id
// the owner's everyday install has always had, so they keep upgrading it in
// place with its login and data. Only release builds are the Play app,
// dev.threeonetwo.seam. A build type can only append a suffix to the
// default id, not replace it, so the variant API sets the whole id here.
androidComponents {
    onVariants { variant ->
        if (variant.buildType != "release") {
            variant.applicationId.set("chat.fluffy.fluffychat.fork")
        }
    }
}

// Which key a release task may use. Only release tasks are checked, so
// debug, profile and tooling tasks build with no key at all.
val requestedTasks = gradle.startParameter.taskNames
val bundlesRelease = requestedTasks.any { it.contains("bundleRelease", ignoreCase = true) }
val buildsRelease = bundlesRelease ||
    requestedTasks.any { it.contains("Release", ignoreCase = true) }
// An unsigned release APK is what F-Droid builds (it then applies Seam's own
// signature from the published APK), so it is allowed when asked for.
val unsignedReleaseAllowed = System.getenv("SEAM_UNSIGNED_RELEASE") == "true"
if (buildsRelease) {
    val releaseKeyError = when {
        appSigningStoreFile != null && uploadStoreFile != null ->
            "Both signing keys are configured. Bundles take the upload key " +
                "(android/key.properties or SEAM_UPLOAD_*), phone APKs the app " +
                "signing key (SEAM_APP_SIGNING_*); set one."
        appSigningStoreFile != null && appSigningPassword == null ->
            "SEAM_APP_SIGNING_KEYSTORE is set without SEAM_APP_SIGNING_PASSWORD."
        bundlesRelease && appSigningStoreFile != null ->
            "Bundles for Play are signed with the upload key, not the app " +
                "signing key: unset SEAM_APP_SIGNING_KEYSTORE and set the upload key."
        bundlesRelease && uploadStoreFile == null ->
            "Release bundles need the upload key: create android/key.properties " +
                "or set SEAM_UPLOAD_STORE_FILE and the other SEAM_UPLOAD_* " +
                "variables (android/store/STORE-LAUNCH.md)."
        appSigningStoreFile == null && uploadStoreFile == null && !unsignedReleaseAllowed ->
            "Release builds need a signing key: SEAM_APP_SIGNING_KEYSTORE and " +
                "SEAM_APP_SIGNING_PASSWORD for an APK that installs over the Play " +
                "build, or the upload key (tools/release/README.md). For an " +
                "unsigned APK, as F-Droid builds, set SEAM_UNSIGNED_RELEASE=true."
        else -> null
    }
    if (releaseKeyError != null) throw GradleException(releaseKeyError)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
    }
}


flutter {
    source = "../.."
}
