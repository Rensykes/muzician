import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.bytebakehouse.muzician"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        val keystoreProperties = Properties()
        val keystorePropertiesFile = rootProject.file("local.properties")
        if (keystorePropertiesFile.exists()) {
            keystoreProperties.load(FileInputStream(keystorePropertiesFile))
        }

        create("release") {
            // This looks at Environment Variables (for GitHub) OR local.properties (for you)
            storeFile = file(System.getenv("ANDROID_KEYSTORE_PATH") 
                ?: keystoreProperties.getProperty("ANDROID_KEYSTORE_PATH") 
                ?: "keystore.jks")
            
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD") 
                ?: keystoreProperties.getProperty("ANDROID_KEYSTORE_PASSWORD")
            
            keyAlias = System.getenv("ANDROID_KEY_ALIAS") 
                ?: keystoreProperties.getProperty("ANDROID_KEY_ALIAS")
            
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD") 
                ?: keystoreProperties.getProperty("ANDROID_KEY_PASSWORD")
        }
    }

    defaultConfig {
        applicationId = "io.bytebakehouse.muzician"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
