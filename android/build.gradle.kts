import java.util.concurrent.TimeUnit

group = "com.example.pretty_awesome_camera"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.2.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.11.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
    id("kotlin-android")
}

// 1.7.0-alpha02 includes the Recorder null-encoder stop guard from b/480772922.
// Without it, stopping a persistent recording while VideoCapture is rebuilding
// after a camera switch can NPE inside CameraX and lose the take (CU-86ajwvee8).
val cameraXVersion = "1.7.0-alpha02"

// Media3 Transformer concatenates salvaged segments. It is NOT version-aligned
// with CameraX: CameraX ships its own recorder stack and pulls in no media3
// artifacts, so there is nothing to align to and this version stands alone.
//
// Transformer specifically, not a hand-rolled MediaExtractor/MediaMuxer merge:
// this plugin had one of those and it was removed for producing malformed
// video. It took track formats from the first segment only, so segments whose
// encoders emitted different codec-specific data were muxed under the wrong
// format — and the mux SUCCEEDED, so no fail-soft path ever ran. Transformer
// reconciles formats and reports failure through onError instead.
val media3Version = "1.8.0"

// Resolved at build time so the app can prove at runtime which plugin build it
// is actually running (see the getBuildInfo method channel call).
val pluginGitSha: String = runCatching {
    val process = ProcessBuilder("git", "rev-parse", "HEAD")
        .directory(projectDir)
        .redirectErrorStream(true)
        .start()
    // Wait before reading: a hung git (credential prompt, locked index) must
    // fall back to "unknown" instead of stalling the build on stream EOF.
    if (!process.waitFor(10, TimeUnit.SECONDS)) {
        process.destroyForcibly()
        null
    } else {
        val output = process.inputStream.bufferedReader().readText().trim()
        if (process.exitValue() == 0 && output.matches(Regex("[0-9a-f]{40}"))) output else null
    }
}.getOrNull() ?: "unknown"

android {
    namespace = "com.example.pretty_awesome_camera"

    compileSdk = 36

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 23
        buildConfigField("String", "CAMERAX_VERSION", "\"$cameraXVersion\"")
        buildConfigField("String", "PLUGIN_GIT_SHA", "\"$pluginGitSha\"")
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

dependencies {
    implementation("androidx.camera:camera-core:$cameraXVersion")
    implementation("androidx.camera:camera-camera2:$cameraXVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraXVersion")
    implementation("androidx.camera:camera-video:$cameraXVersion")
    implementation("androidx.camera:camera-view:$cameraXVersion")

    implementation("androidx.media3:media3-transformer:$media3Version")
    implementation("androidx.media3:media3-common:$media3Version")
    implementation("androidx.media3:media3-effect:$media3Version")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
