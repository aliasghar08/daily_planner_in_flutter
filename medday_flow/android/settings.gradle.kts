pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val localProps = file("local.properties")
        require(localProps.exists()) { "local.properties not found" }
        localProps.inputStream().use { properties.load(it) }

        val path = properties.getProperty("flutter.sdk")
        require(path != null) { "flutter.sdk not set in local.properties" }
        path
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        maven {
            url = uri("https://repo1.maven.org/maven2/")
        }
        maven {
            url = uri("https://maven.google.com")
        }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false  // ✅ Updated from 8.7.0
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false  // ✅ Updated from 2.1.0
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")