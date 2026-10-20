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
 * When nothing is supplied we fall back to Google's public *test* id, which
 * is fine for debug and profile builds and useless for a release build - so
 * [requireReleaseAdMobAppId] fails any release task that would ship it.
 */
val googleTestAdMobAppId = "ca-app-pub-3940256099942544~3347511713"
val configuredAdMobAppId: String =
    (project.findProperty("admobAppId") as String?)
        ?: System.getenv("ORG_GRADLE_PROJECT_admobAppId")
        ?: System.getenv("ADMOB_APP_ID")
        ?: ""

/** True when no AdMob application id was supplied at all. */
val isAdMobAppIdMissing: Boolean = configuredAdMobAppId.isBlank()

/** True when the configured id is Google's public test id rather than a real one. */
val isGoogleTestAdMobAppId: Boolean = configuredAdMobAppId == googleTestAdMobAppId

/**
 * Whether a release build may deliberately ship Google's public test ids.
 *
 * Resolution order:
 *  1. `-PallowTestAdMobIds=true` on the Gradle command line
 *  2. `ORG_GRADLE_PROJECT_allowTestAdMobIds=true` in the environment
 *  3. `ALLOW_TEST_ADMOB_IDS=true` in the environment
 *
 * The release pipeline sets this when it falls back to the public test ids
 * because no AdMob account is configured yet. The shipped app then shows
 * Google's test ads and earns nothing - a deliberate, warned-about state
 * rather than an accident.
 */
val allowTestAdMobIds: Boolean =
    (project.findProperty("allowTestAdMobIds") as String?)?.toBooleanStrictOrNull()
        ?: (System.getenv("ORG_GRADLE_PROJECT_allowTestAdMobIds")
            ?: System.getenv("ALLOW_TEST_ADMOB_IDS"))
            ?.trim()
            ?.equals("true", ignoreCase = true)
        ?: false

/**
 * Fails a release build that has no AdMob application id, or that would ship
 * Google's public test id without saying so.
 *
 * The release pipeline used to leave `ADMOB_*` unset, so `AdService` fell back
 * to Google's test ad units and the shipped APK showed test ads. A missing id
 * is always fatal (an empty id would break the AdMob SDK at start-up); a test
 * id is fatal unless it was asked for, so a real account cannot be forgotten.
 */
// The gate runs in `doFirst` on every release task, so the warning is
// printed once per build rather than once per task.
var warnedAboutTestAdMobIds = false

fun requireReleaseAdMobAppId() {
    if (isAdMobAppIdMissing) {
        throw GradleException(
            "A release build needs an AdMob application id. Pass " +
                "-PadmobAppId=ca-app-pub-... or set ORG_GRADLE_PROJECT_admobAppId.",
        )
    }
    if (isGoogleTestAdMobAppId) {
        if (!allowTestAdMobIds) {
            throw GradleException(
                "A release build needs a real AdMob application id. Pass " +
                    "-PadmobAppId=ca-app-pub-... or set ORG_GRADLE_PROJECT_admobAppId. " +
                    "Google's public test id ($googleTestAdMobAppId) ships test ads and " +
                    "earns nothing. If that is deliberate, set ALLOW_TEST_ADMOB_IDS=true.",
            )
        }
        if (!warnedAboutTestAdMobIds) {
            warnedAboutTestAdMobIds = true
            println(
                "WARNING: shipping Google's public test AdMob id: the app will " +
                    "serve test ads and earn nothing until a real AdMob account is " +
                    "configured.",
            )
        }
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
        // and profile fall back to the public test id; release overrides it
        // with the real one (or fails the build).
        manifestPlaceholders["admobAppId"] =
            if (isAdMobAppIdMissing) googleTestAdMobAppId else configuredAdMobAppId
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
            // The public test AdMob id is fine here: debug builds show test ads.
            manifestPlaceholders["admobAppId"] = googleTestAdMobAppId
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
