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
}

val requiredSigningProperties = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")

/**
 * A release build must fail closed when the upload keystore is missing or
 * incomplete. There is deliberately no debug-signing fallback: a release that
 * cannot be signed with the registered upload key is an error, not a build
 * that silently ships a debug-signed artifact.
 */
fun requireReleaseSigning() {
    if (!keystorePropertiesFile.exists()) {
        throw GradleException(
            "A release build needs android/key.properties with keyAlias, keyPassword, " +
                "storeFile and storePassword. Refusing to fall back to the debug signing key.",
        )
    }
    val missing = requiredSigningProperties.filter {
        keystoreProperties.getProperty(it).isNullOrBlank()
    }
    if (missing.isNotEmpty()) {
        throw GradleException(
            "A release build needs non-empty signing properties; missing: " +
                "${missing.joinToString(", ")}. Refusing to fall back to the debug signing key.",
        )
    }
    val storeFile = file(keystoreProperties.getProperty("storeFile"))
    if (!storeFile.isFile) {
        throw GradleException(
            "The release keystore configured by android/key.properties does not exist: " +
                storeFile.path,
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
            // The release variant is signed only by the upload keystore.
            // requireReleaseSigning() fails the build when key.properties is
            // missing or incomplete, so this can never fall back to debug.
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
            // Debug builds keep the standard debug keystore; the release
            // validation above never applies to them.
            signingConfig = signingConfigs.getByName("debug")
            // The public test AdMob id is fine here: debug builds show test ads.
            manifestPlaceholders["admobAppId"] = googleTestAdMobAppId
        }
        // No `profile` block: AGP 9's DSL does not expose a profile build type
        // here, and the profile variant inherits the placeholder from
        // `defaultConfig` anyway.
    }
}

// A release build must never ship the sample AdMob id or a debug-signed
// artifact. Every task in the release graph is hooked, so the build fails on
// the first one to run - `flutter build appbundle` drives `bundleRelease`, not
// `assembleRelease`, and hooking only one of them would let the other slip
// through.
tasks.matching { it.name.contains("Release") }.configureEach {
    doFirst {
        requireReleaseSigning()
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
