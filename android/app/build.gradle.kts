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

// Release builds are signed with the Play upload key, which never enters
// the repo. Its path and passwords come from android/key.properties
// (gitignored, like every *.jks and *.keystore) or, for any value that file
// does not set, from SEAM_UPLOAD_* environment variables. A storeFile path
// is resolved against android/app. android/store/STORE-LAUNCH.md covers
// creating the key.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
fun uploadKeyValue(property: String, env: String): String? =
    keystoreProperties.getProperty(property) ?: System.getenv(env)
val uploadStoreFile = uploadKeyValue("storeFile", "SEAM_UPLOAD_STORE_FILE")

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
        if (uploadStoreFile != null) {
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
        // the same values by build mode.
        manifestPlaceholders["appUrlScheme"] = "dev.threeonetwo.seam"
        manifestPlaceholders["appSsoUrlScheme"] = "dev.threeonetwo.seam.auth"
        ndk { // Workaround for https://github.com/flutter/flutter/issues/162153#issuecomment-2612443642
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64", "x86")
        }
    }

    buildTypes {
        // Debug and profile builds keep the URL schemes of the owner's
        // long-lived install, which was set up under them.
        debug {
            manifestPlaceholders["appUrlScheme"] = "im.fluffychat"
            manifestPlaceholders["appSsoUrlScheme"] = "im.fluffychat.auth"
        }
        // Flutter's profile build type is copied from debug before the block
        // above applies, so it needs the same values set again.
        getByName("profile") {
            manifestPlaceholders["appUrlScheme"] = "im.fluffychat"
            manifestPlaceholders["appSsoUrlScheme"] = "im.fluffychat.auth"
        }
        release {
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

// A release build without the upload key would come out unsigned, which
// Play refuses, so stop before building one.
if (uploadStoreFile == null &&
    gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
) {
    throw GradleException(
        "Release builds need the upload key: create android/key.properties " +
            "or set SEAM_UPLOAD_STORE_FILE and the other SEAM_UPLOAD_* " +
            "variables (android/store/STORE-LAUNCH.md).",
    )
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
    }
}


flutter {
    source = "../.."
}
