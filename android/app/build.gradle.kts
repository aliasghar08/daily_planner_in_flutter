import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin") // Flutter plugin
}

// --- Load Flutter properties from local.properties ---
val localProps = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

val flutterVersionCode = (localProps.getProperty("flutter.versionCode") ?: "1").toInt()
val flutterVersionName = localProps.getProperty("flutter.versionName") ?: "1.0.0"

android {
    namespace = "com.example.daily_planner"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.example.daily_planner"
        minSdk = 24         
        targetSdk = 36
        versionCode = flutterVersionCode
        versionName = flutterVersionName

        manifestPlaceholders["googleRedirectScheme"] =
            "com.googleusercontent.apps.777337977048-vf0nr3plk0e3k5h11u4r1gqsqrbm9o2u"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_21.toString()
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug") // Replace with release key later
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// Dependencies
dependencies {
    // Core library desugaring for modern Java APIs
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Firebase Auth
    implementation("com.google.firebase:firebase-auth-ktx:22.3.0")

    // Google Sign-In
    implementation("com.google.android.gms:play-services-auth:21.0.0")

    // WorkManager for background tasks
    implementation("androidx.work:work-runtime-ktx:2.8.1")

}

// ✅ Important: DO NOT add any `flutter { source = ... }` block here
