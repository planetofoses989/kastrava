plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "pp.ua.kastrava"
    compileSdk = 34

    defaultConfig {
        applicationId = "pp.ua.kastrava"
        minSdk = 26
        targetSdk = 34
        // Mirrors the desktop release: 101.0.0.
        versionCode = 1010000
        versionName = "101.0.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        viewBinding = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.preference:preference-ktx:1.2.1")
    implementation("com.google.android.material:material:1.12.0")
    // Ed25519 license-signature verification on every API level
    // (java.security Ed25519 needs API 33+; BouncyCastle covers 26+).
    implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")
}
