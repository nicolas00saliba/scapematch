import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.isFile) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun signingValue(property: String, envName: String): String? {
    val fromFile = keystoreProperties.getProperty(property)?.trim()
    if (!fromFile.isNullOrEmpty()) return fromFile
    val fromEnv = System.getenv(envName)?.trim()
    if (!fromEnv.isNullOrEmpty()) return fromEnv
    return null
}

fun Project.resolveStoreFile(path: String): File? {
    val absolute = File(path)
    if (absolute.isAbsolute && absolute.isFile) return absolute
    val fromModule = file(path)
    if (fromModule.isFile) return fromModule
    val fromAndroid = rootProject.file(path)
    if (fromAndroid.isFile) return fromAndroid
    return null
}

val releaseStorePassword = signingValue("storePassword", "ANDROID_STORE_PASSWORD")
val releaseKeyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseStorePath = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
val releaseStore = releaseStorePath?.let { resolveStoreFile(it) }
val hasReleaseSigning = releaseStore != null &&
    !releaseStorePassword.isNullOrEmpty() &&
    !releaseKeyPassword.isNullOrEmpty() &&
    !releaseKeyAlias.isNullOrEmpty()
val ciRelease = System.getenv("CI") == "true" ||
    System.getenv("GITHUB_ACTIONS") == "true"

android {
    namespace = "dev.scapematch.scapematch"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.scapematch.scapematch"
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

    if (hasReleaseSigning) {
        val alias = releaseKeyAlias ?: error("keyAlias ausente")
        val keyPass = releaseKeyPassword ?: error("keyPassword ausente")
        val storePass = releaseStorePassword ?: error("storePassword ausente")
        val store = releaseStore ?: error("storeFile ausente")
        signingConfigs {
            create("release") {
                keyAlias = alias
                keyPassword = keyPass
                storePassword = storePass
                storeFile = store
            }
        }
    }

    buildTypes {
        release {
            // Local sem key.properties continua assinando com a keystore de debug.
            // No CI, a task de release falha se a keystore de release não estiver presente.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

if (ciRelease && !hasReleaseSigning) {
    val appProject = project
    gradle.taskGraph.whenReady {
        val releasing = allTasks.any { task ->
            task.project == appProject && task.name.endsWith("Release")
        }
        if (releasing) {
            error(
                "Build de release no CI exige a keystore de release. " +
                    "Informe android/key.properties (storeFile, storePassword, keyAlias, keyPassword) " +
                    "ou ANDROID_KEYSTORE_PATH, ANDROID_STORE_PASSWORD, ANDROID_KEY_ALIAS e ANDROID_KEY_PASSWORD. " +
                    "A keystore de debug não assina release no CI.",
            )
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
