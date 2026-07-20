group = "com.adrianczuczka.audio_stream_player"
version = "1.0.0"

buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.9.1")
    }
}

// Kotlin sources are compiled by Flutter's built-in Kotlin support; applying
// the Kotlin Gradle Plugin here is deprecated and must be avoided.
plugins {
    id("com.android.library")
}

rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

android {
    namespace = "com.adrianczuczka.audio_stream_player"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 21
    }
}
