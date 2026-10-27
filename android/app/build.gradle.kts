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

/** Release tasks fail closed; debug and profile never need live IDs or signing. */
fun requireReleaseAdMobAppId() {
    if (isAdMobAppIdMissing) {
        throw GradleException(
            "A release build needs an AdMob application id. Pass " +
                "-PadmobAppId=ca-app-pub-... or set ORG_GRADLE_PROJECT_admobAppId.",
        )
    }
    if (!Regex("^ca-app-pub-[0-9]{16}~[0-9]{10}$").matches(configuredAdMobAppId) ||
        configuredAdMobAppId.startsWith("ca-app-pub-3940256099942544")) {
        throw GradleException("A release build needs a valid, non-sample AdMob application id.")
    }
    val requiredSigning = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
    if (!keystorePropertiesFile.exists() || requiredSigning.any {
            keystoreProperties.getProperty(it).isNullOrBlank()
        } || !file(keystoreProperties.getProperty("storeFile")).isFile) {
        throw GradleException("A release build needs the registered upload keystore and all signing properties.")
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
        manifestPlaceholders["admobAppId"] = googleTestAdMobAppId
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
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            manifestPlaceholders["admobAppId"] = configuredAdMobAppId
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
