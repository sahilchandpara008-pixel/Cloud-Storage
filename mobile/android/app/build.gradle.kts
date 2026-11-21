plugins {
    id("com.android.application")
    // Firebase config for both app ids (com.cloudstorage.app, com.flixvault.app).
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.cloudstorage.cloud_storage"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.cloudstorage.app"
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
    }

    // One fixed key for every tester build, so the organic and ads APKs can
    // update each other. TESTING ONLY: create a new private key (kept out of
    // the repo) before any Play Store release.
    signingConfigs {
        create("tester") {
            storeFile = file("tester-release.jks")
            storePassword = "cloudstorage-tester"
            keyAlias = "cloudstorage"
            keyPassword = "cloudstorage-tester"
        }
    }

    // direct = APKs shared outside Play (ads / website), UPI only, no Google code.
    // play   = Play Store build: same app + Google Play "alternative billing
    //          only" (Google's info screen + transaction report; payment is
    //          still the same UPI flow).
    flavorDimensions += "store"
    productFlavors {
        create("direct") { dimension = "store" }
        // Play Store app id (permanent once uploaded). Shared APKs keep
        // com.cloudstorage.app so existing installs keep updating.
        create("play") {
            dimension = "store"
            applicationId = "com.flixvault.app"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("tester")
        }
        debug {
            signingConfig = signingConfigs.getByName("tester")
        }
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

dependencies {
    "playImplementation"("com.android.billingclient:billing-ktx:8.0.0")
}
