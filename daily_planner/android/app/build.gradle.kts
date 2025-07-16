plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.daily_planner"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true

    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.daily_planner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
manifestPlaceholders.put(
    "googleRedirectScheme",
    "com.googleusercontent.apps.777337977048-vf0nr3plk0e3k5h11u4r1gqsqrbm9o2u"
)

    }

   buildTypes {
    release {
        signingConfig = signingConfigs.getByName("debug") // Replace with real release signing for production
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro"
        )
    }
}

}

flutter {
    source = "../.."
}

dependencies {
 coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    implementation("com.google.firebase:firebase-auth-ktx:22.3.0")
implementation("com.google.android.gms:play-services-auth:21.0.0")

}

apply(plugin = "com.google.gms.google-services")
