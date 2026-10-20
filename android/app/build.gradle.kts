import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

/**
 * The AdMob application id that goes into the manifest.
 *
 * Resolution order:
 *  1. `-PadmobAppId=...` on the Gradle command line
 *  2. `ORG_GRADLE_PROJECT_admobAppId=...` in the environment (Codemagic sets this)
 *  3. `ADMOB_APP_ID=...` in the environment
 *
 * When nothing is supplied we fall back to Google's public *sample* id, which
 * is fine for debug and profile builds and useless for a release build - so
 * [requireReleaseAdMobAppId] fails any release task that would ship it.
 */
val googleSampleAdMobAppId = "ca-app-pub-3940256099942544~3347511713"
val configuredAdMobAppId: String =
    (project.findProperty("admobAppId") as String?)
        ?: System.getenv("ORG_GRADLE_PROJECT_admobAppId")
        ?: System.getenv("ADMOB_APP_ID")
        ?: ""

/** True when the configured id is the public sample id rather than a real one. */
val isSampleAdMobAppId: Boolean =
    configuredAdMobAppId.isBlank() || configuredAdMobAppId == googleSampleAdMobAppId

/**
 * Fails a release build that would ship the sample AdMob id.
 *
 * The release pipeline used to leave `ADMOB_*` unset, so `AdService` fell back
 * to Google's test ad units and the shipped APK showed test ads. A release
 * build must carry a real application id, so this turns a silent revenue bug
 * into a build failure.
 */
fun requireReleaseAdMobAppId() {
    if (isSampleAdMobAppId) {
        throw GradleException(
            "A release build needs a real AdMob application id. Pass " +
                "-PadmobAppId=ca-app-pub-... or set ORG_GRADLE_PROJECT_admobAppId. " +
                "The sample id (ca-app-pub-3940256099942544~3347511713) is only " +
                "allowed in debug and profile builds.",
        )
    }
}

android {
    namespace = "app.xynix.lynk"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.xynix.lynk"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        // The manifest holds the AdMob application id as a placeholder. Debug
        // and profile fall back to the public sample id; release overrides it
        // with the real one (or fails the build).
        manifestPlaceholders["admobAppId"] =
            if (isSampleAdMobAppId) googleSampleAdMobAppId else configuredAdMobAppId
        // Real phones only: drops the ~21 MB of x86_64/x86 emulator libs that
        // flutter_webrtc and ML Kit otherwise bundle for every ABI.
        // Skipped under --split-per-abi (Flutter injects its own filters).
        if (!project.hasProperty("split-per-abi")) {
            ndk {
                abiFilters += listOf("arm64-v8a", "armeabi-v7a")
            }
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
            // Shrink and obfuscate the release build. Without this the APK
            // ships every dependency class name and the Dart symbols.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            // The sample AdMob id is fine here: debug builds show test ads.
            manifestPlaceholders["admobAppId"] = googleSampleAdMobAppId
        }
        // No `profile` block: AGP 9's DSL does not expose a profile build type
        // here, and the profile variant inherits the placeholder from
        // `defaultConfig` anyway.
    }
}

// A release build must never ship the sample AdMob id. Every task in the
// release graph is hooked, so the build fails on the first one to run -
// `flutter build appbundle` drives `bundleRelease`, not `assembleRelease`,
// and hooking only one of them would let the other slip through.
tasks.matching { it.name.contains("Release") }.configureEach {
    doFirst {
        requireReleaseAdMobAppId()
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
