import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.serenut.pos"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.serenut.pos"
        // You can update the following values to match your application needs.
        // For more information, see: https://docs.flutter.dev/deployment/android#reviewing-the-gradle-build-configuration.
        minSdk = 21
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }

    signingConfigs {
        create("release") {
            val keyFile = keystoreProperties["storeFile"] as String? ?: System.getenv("KEYSTORE_FILE") ?: "serenut-release.jks"
            val storePass = keystoreProperties["storePassword"] as String? ?: System.getenv("KEYSTORE_PASSWORD")
            val alias = keystoreProperties["keyAlias"] as String? ?: System.getenv("KEY_ALIAS")
            val keyPass = keystoreProperties["keyPassword"] as String? ?: System.getenv("KEY_PASSWORD")

            if (file(keyFile).exists() && !storePass.isNullOrEmpty() && !alias.isNullOrEmpty()) {
                storeFile = file(keyFile)
                storePassword = storePass
                keyAlias = alias
                keyPassword = keyPass ?: storePass
                storeType = "PKCS12"
            } else {
                throw GradleException(
                    "Release signing is not configured. Provide android/key.properties " +
                        "or KEYSTORE_FILE, KEYSTORE_PASSWORD, KEY_ALIAS and KEY_PASSWORD."
                )
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Ek bağımlılıklar
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.core:core-ktx:1.10.1")
    implementation("com.google.android.material:material:1.9.0")
    // Sunmi SDK'yı ekleyelim
    implementation("com.sunmi:printerlibrary:1.0.18")
    // AndroidPrintSDK JAR
    implementation(files("libs/androidprintsdk.jar"))
}

// JitPack repository
repositories {
    maven { url = uri("https://jitpack.io") }
    google()
    mavenCentral()
    flatDir {
        dirs("libs")
    }
}
