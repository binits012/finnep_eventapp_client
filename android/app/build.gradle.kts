import java.io.FileInputStream
import java.util.Properties
import org.gradle.api.tasks.Copy
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val releaseSigningConfigured =
    keystorePropertiesFile.exists() &&
        !keystoreProperties.getProperty("keyAlias").isNullOrBlank() &&
        !keystoreProperties.getProperty("keyPassword").isNullOrBlank() &&
        !keystoreProperties.getProperty("storePassword").isNullOrBlank() &&
        !keystoreProperties.getProperty("storeFile").isNullOrBlank()
val requestedTasks = gradle.startParameter.taskNames.joinToString(" ").lowercase()
val isReleaseTaskRequested = requestedTasks.contains("release")

android {
    namespace = "com.okazzo.client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"
    flavorDimensions += "region"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_11)
        }
    }

    signingConfigs {
        create("release") {
            if (releaseSigningConfigured) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile")!!)
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    defaultConfig {
        applicationId = "com.finnep.finnep_eventapp_client"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    productFlavors {
        create("au") {
            dimension = "region"
            applicationId = "com.okazzo.client.au"
            resValue("string", "app_name", "Okazzo AUS")
        }
        create("eu") {
            dimension = "region"
            applicationId = "com.okazzo.client.eu"
            resValue("string", "app_name", "Okazzo EU")
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
        }
        release {
            if (isReleaseTaskRequested && !releaseSigningConfigured) {
                throw GradleException(
                    "Missing android/key.properties for release signing. " +
                        "Copy android/key.properties.example and fill values (prefer ~/keystores/... path).",
                )
            }
            signingConfig =
                if (releaseSigningConfigured) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
}

flutter {
    source = "../.."
}

// Make plain `flutter run` (assembleDebug) work with flavors by defaulting to EU debug output.
tasks.register<Copy>("copyEuDebugApkForFlutterRun") {
    from(layout.buildDirectory.file("outputs/apk/eu/debug/app-eu-debug.apk"))
    into(layout.buildDirectory.dir("outputs/flutter-apk"))
    rename("app-eu-debug.apk", "app-debug.apk")
}

tasks.matching { it.name == "assembleDebug" }.configureEach {
    dependsOn("assembleEuDebug")
    finalizedBy("copyEuDebugApkForFlutterRun")
}
