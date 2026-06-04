plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Google Services plugin for Firebase
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.talkmate_ai"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.talkmate_ai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Disable code shrinking/obfuscation to avoid R8 issues during setup
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
    implementation(platform("org.jetbrains.kotlin:kotlin-bom:1.9.22"))

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
