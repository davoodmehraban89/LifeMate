import java.util.Base64
import java.security.KeyStore
import java.security.cert.X509Certificate
import javax.naming.ldap.LdapName

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
// A separate, debug-only device edition. The published online identity stays fixed.
val devicePlannerOnly = providers.gradleProperty("lifeguideDevicePlanner").orNull == "true"
// Never-distributed synthetic acceptance identity, not a replacement user APK.
val personalRecoveryQa = providers.gradleProperty("lifeguidePersonalRecoveryQa").orNull == "true"
val requestedTasks = gradle.startParameter.taskNames.map { it.substringAfterLast(':').lowercase() }
val assembling = requestedTasks.any { it.startsWith("assemble") || it.startsWith("bundle") }
val decodedDefines = providers.gradleProperty("dart-defines").orNull.orEmpty()
    .split(',').filter { it.isNotBlank() }.map { String(Base64.getDecoder().decode(it)) }
val standaloneDefine = decodedDefines.contains("LIFEGUIDE_STANDALONE=true")
val recoveryDefine = decodedDefines.contains("LIFEGUIDE_PERSONAL_RECOVERY_QA=true")
val dartTarget = providers.gradleProperty("target").orNull.orEmpty().replace('\\', '/')
val recoveryTarget = dartTarget.endsWith("tool/personal_recovery_fixture.dart")
if (personalRecoveryQa && !devicePlannerOnly) {
    throw GradleException("Synthetic recovery QA requires the isolated device planner.")
}
if (assembling && personalRecoveryQa && !(standaloneDefine && recoveryDefine && recoveryTarget)) {
    throw GradleException("Synthetic recovery QA requires its matching defines and entry point.")
}
if (assembling && !personalRecoveryQa && (recoveryDefine || recoveryTarget)) {
    throw GradleException("Recovery fixtures cannot be packaged as a user application.")
}
if (devicePlannerOnly) {
    if (requestedTasks.any { it.contains("release") || it.contains("profile") || it == "assemble" || it == "bundle" }) {
        throw GradleException("The independent device planner is a debug-only initial edition.")
    }
    if (assembling && !standaloneDefine) {
        throw GradleException("Device planner builds require the matching LIFEGUIDE_STANDALONE define.")
    }
    if (assembling && !(dartTarget.endsWith("lib/standalone_main.dart") || dartTarget.endsWith("tool/standalone_acceptance_fixture.dart") || (personalRecoveryQa && recoveryTarget))) {
        throw GradleException("The device edition requires its isolated Dart entry point.")
    }
} else if (assembling && standaloneDefine) {
    throw GradleException("Standalone Dart cannot be packaged as the online application.")
}
val releaseEnvironment = listOf("LIFEGUIDE_KEYSTORE_PATH", "LIFEGUIDE_KEYSTORE_PASSWORD", "LIFEGUIDE_KEY_ALIAS", "LIFEGUIDE_KEY_PASSWORD")
val signingValues = releaseEnvironment.associateWith { System.getenv(it) }
if (releaseRequested) {
    val missing = signingValues.filterValues { it.isNullOrBlank() }.keys
    if (missing.isNotEmpty()) throw GradleException("Release signing requires environment variables: ${missing.joinToString()}")
    val keyFile = file(signingValues.getValue("LIFEGUIDE_KEYSTORE_PATH")!!)
    val releaseAlias = signingValues.getValue("LIFEGUIDE_KEY_ALIAS")!!
    if (!keyFile.isFile || keyFile.name.equals("debug.keystore", ignoreCase = true) || releaseAlias.equals("androiddebugkey", ignoreCase = true)) {
        throw GradleException("A real owner-supplied release keystore is required.")
    }
    val keyStore = try {
        KeyStore.getInstance(keyFile, signingValues.getValue("LIFEGUIDE_KEYSTORE_PASSWORD")!!.toCharArray())
    } catch (_: Exception) {
        throw GradleException("The owner-supplied release keystore could not be opened.")
    }
    val certificate = keyStore.getCertificate(releaseAlias) as? X509Certificate
    if (!keyStore.isKeyEntry(releaseAlias) || certificate == null) {
        throw GradleException("The release signing alias must contain a private key and certificate.")
    }
    if (LdapName(certificate.subjectX500Principal.name).rdns.any { it.type.equals("CN", ignoreCase = true) && it.value.toString().equals("Android Debug", ignoreCase = true) }) {
        throw GradleException("Android debug certificates are forbidden for release signing.")
    }
    val defines = providers.gradleProperty("dart-defines").orNull.orEmpty().split(',').filter { it.isNotBlank() }
    if (defines.any { String(Base64.getDecoder().decode(it)).startsWith("LIFEGUIDE_DEBUG_CA_BASE64=") && String(Base64.getDecoder().decode(it)).substringAfter('=').isNotEmpty() }) {
        throw GradleException("Development CA input is forbidden in release builds.")
    }
}

android {
    namespace = "ir.lifeguide.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    buildFeatures { buildConfig = true }
    if (devicePlannerOnly) {
        sourceSets.getByName("debug").manifest.srcFile(if (personalRecoveryQa) "src/recoveryQa/AndroidManifest.xml" else "src/devicePlanner/AndroidManifest.xml")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = when {
            personalRecoveryQa -> "ir.lifeguide.app.personal"
            devicePlannerOnly -> "ir.lifeguide.app.device"
            else -> "ir.lifeguide.app"
        }
        buildConfigField("boolean", "DEVICE_PLANNER_ONLY", devicePlannerOnly.toString())
        buildConfigField("boolean", "PERSONAL_RECOVERY_QA", personalRecoveryQa.toString())
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
        if (assembling && personalRecoveryQa && (flutter.versionCode !in 10..11 || flutter.versionName != "0.7.2-recovery-qa.${flutter.versionCode}")) {
            throw GradleException("Only private synthetic recovery QA versions 10 and 11 are allowed.")
        }
    }

    signingConfigs {
        create("release") {
            signingValues["LIFEGUIDE_KEYSTORE_PATH"]?.let { storeFile = file(it) }
            storePassword = signingValues["LIFEGUIDE_KEYSTORE_PASSWORD"]
            keyAlias = signingValues["LIFEGUIDE_KEY_ALIAS"]
            keyPassword = signingValues["LIFEGUIDE_KEY_PASSWORD"]
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
