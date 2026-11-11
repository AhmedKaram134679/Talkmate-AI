import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Google Services plugin for Firebase
    id("com.google.gms.google-services")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val hasReleaseKey = keystorePropertiesFile.exists()

// A release build must never be signed with the public debug key by accident.
// CI jobs that only need a release-mode compile can opt in explicitly:
//   set ORG_GRADLE_PROJECT_allowDebugSigning=true in the environment
val isReleaseTask = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
val allowDebugSigning = (project.findProperty("allowDebugSigning") as String?) == "true"
if (isReleaseTask && !hasReleaseKey && !allowDebugSigning) {
    throw GradleException(
        "android/key.properties is missing: refusing to sign a release build with the debug key. " +
            "Create key.properties (see key.properties.example) or set the ORG_GRADLE_PROJECT_allowDebugSigning=true environment variable for CI-only builds."
    )
}

android {
    namespace = "com.talkmate.ai"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKey) {
                fun requiredProp(name: String): String =
                    keystoreProperties.getProperty(name)
                        ?: throw GradleException("key.properties is missing the '$name' entry")
                keyAlias = requiredProp("keyAlias")
                keyPassword = requiredProp("keyPassword")
                storeFile = file(requiredProp("storeFile"))
                storePassword = requiredProp("password")
            }
        }
    }

    defaultConfig {
        applicationId = "com.talkmate.ai"
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Debug signing is reachable only with allowDebugSigning=true (see the guard above).
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // Ensure the Java toolchain uses JDK 17 for all Java/Kotlin compilation
    @Suppress("UnstableApiUsage")
    buildFeatures {}
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring for Java 8+ APIs on older Android versions
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    
    // Firebase BoM and Services
    implementation(platform("com.google.firebase:firebase-bom:34.7.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-messaging")

    // AndroidX & Kotlin Standard Libraries
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")

    // WebRTC Native Library (Explicitly added to resolve AudioSink for NativeAudioTrackSink)
    implementation("io.github.webrtc-sdk:android:137.7151.04")
}

// --- Export APKs/AABs and ensure Flutter-expected path is populated ---
afterEvaluate {
    // Attach copy logic directly to assemble tasks
    tasks.matching { it.name.startsWith("assemble") && it.name != "assemble" }.configureEach {
        val variantCap = name.removePrefix("assemble")
        if (variantCap.isEmpty()) return@configureEach
        val variantLower = variantCap.replaceFirstChar { it.lowercase() }
        doLast {
            // Prefer legacy AGP dir, else fallback to flutter-apk
            val legacyApkDir = file("$buildDir/outputs/apk/${variantLower}")
            val outDir = if (legacyApkDir.exists()) legacyApkDir else file("$buildDir/outputs/flutter-apk")
            if (!outDir.exists()) {
                println("[export-apk] Output directory not found: ${outDir}")
                return@doLast
            }
            val apks = outDir.listFiles { _, n -> n.endsWith(".apk", ignoreCase = true) }?.toList() ?: emptyList()
            if (apks.isEmpty()) {
                println("[export-apk] No APKs found in: ${outDir}")
                return@doLast
            }
            val apk = apks.maxByOrNull { it.length() }!!
            val targetName = when (variantLower) {
                "debug" -> "app-debug.apk"
                "release" -> "app-release.apk"
                "profile" -> "app-profile.apk"
                else -> "app-${variantLower}.apk"
            }
            // Copy EXACTLY to Flutter's expected module path
            val flutterDir = File(buildDir, "outputs/flutter-apk")
            if (!flutterDir.exists()) flutterDir.mkdirs()
            val flutterDest = File(flutterDir, targetName)
            apk.copyTo(flutterDest, overwrite = true)
            println("[export-apk] Ensured flutter-apk contains ${flutterDest.name}")

            // Also copy to projectRoot/build/app/outputs/flutter-apk (Flutter CLI usually looks here)
            val projectRoot = rootDir.parentFile
            val rootFlutterDir = File(projectRoot, "build/app/outputs/flutter-apk")
            if (!rootFlutterDir.exists()) rootFlutterDir.mkdirs()
            val rootFlutterDest = File(rootFlutterDir, targetName)
            apk.copyTo(rootFlutterDest, overwrite = true)
            println("[export-apk] Ensured root build/app/outputs/flutter-apk contains ${rootFlutterDest.relativeTo(projectRoot)}")
        }
    }

    // Attach copy logic directly to bundle tasks (AAB)
    tasks.matching { it.name.startsWith("bundle") && it.name != "bundle" }.configureEach {
        val variantCap = name.removePrefix("bundle")
        if (variantCap.isEmpty()) return@configureEach
        val variantLower = variantCap.replaceFirstChar { it.lowercase() }
        doLast {
            val outDir = file("$buildDir/outputs/bundle/${variantLower}")
            if (!outDir.exists()) {
                println("[export-aab] Output directory not found: ${outDir}")
                return@doLast
            }
            val aabs = outDir.listFiles { _, n -> n.endsWith(".aab", ignoreCase = true) }?.toList() ?: emptyList()
            if (aabs.isEmpty()) {
                println("[export-aab] No AABs found in: ${outDir}")
                return@doLast
            }
            val aab = aabs.maxByOrNull { it.length() }!!
            val destDir = File(rootDir, "build/aab")
            if (!destDir.exists()) destDir.mkdirs()
            val targetName = when (variantLower) {
                "debug" -> "app-debug.aab"
                "release" -> "app-release.aab"
                "profile" -> "app-profile.aab"
                else -> "app-${variantLower}.aab"
            }
            val destFile = File(destDir, targetName)
            aab.copyTo(destFile, overwrite = true)
            println("[export-aab] Copied ${aab.name} -> ${destFile.relativeTo(rootDir)}")
        }
    }
}
