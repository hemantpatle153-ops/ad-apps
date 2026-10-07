import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing reads android/key.properties (never commit it or the keystore).
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

// --dart-define values that `flutter build` passes on (base64, comma separated).
val dartDefines: Map<String, String> = (project.findProperty("dart-defines") as String?).orEmpty()
    .split(",").filter { it.isNotEmpty() }
    .map { String(Base64.getDecoder().decode(it)) }
    .associate { it.substringBefore("=") to it.substringAfter("=", "") }

// --dart-define=ADS=off ships the app without ads: no AdMob IDs are needed and
// release builds drop the advertising ID permission (src/noads).
val adsOff = dartDefines["ADS"] == "off"

android {
    namespace = "in.onlysoftware.doc_scanner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "in.onlysoftware.doc_scanner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // AdMob app ID. Google's test ID by default; release builds pass
        // the real one with -PadmobAppId=ca-app-pub-xxx~yyy
        manifestPlaceholders["admobAppId"] =
            (project.findProperty("admobAppId") as String?)
                ?: "ca-app-pub-3940256099942544~3347511713"
    }

    signingConfigs {
        create("release") {
            if (keyProperties.isNotEmpty()) {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    if (adsOff) {
        sourceSets.getByName("release").manifest.srcFile("src/noads/AndroidManifest.xml")
    }

    buildTypes {
        release {
            // Falls back to debug keys until key.properties exists, so
            // `flutter run --release` still works on a phone.
            signingConfig = if (keyProperties.isNotEmpty())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
        }
    }
}

// A Play upload must be signed with the upload key, and either show real ads
// or be built with ads off. Stop an app bundle build that would silently use
// debug keys or Google's test ads.
gradle.taskGraph.whenReady {
    if (allTasks.none { it.name == "bundleRelease" }) return@whenReady
    val missing = mutableListOf<String>()
    if (keyProperties.isEmpty()) missing += "android/key.properties (upload key)"
    if (!adsOff) {
        if (project.findProperty("admobAppId") == null) missing += "-PadmobAppId"
        listOf("ADMOB_BANNER_ID", "ADMOB_INTERSTITIAL_ID").filterNot { it in dartDefines }
            .forEach { missing += "--dart-define=$it" }
    }
    if (missing.isNotEmpty()) {
        throw GradleException(
            "Play release bundle needs: ${missing.joinToString()} " +
                "(or --dart-define=ADS=off for no ads). See README.md (Release build).")
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
