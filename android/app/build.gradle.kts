import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val buyerLinkHost = providers.gradleProperty("BAGOO_LINK_HOST")
    .orElse("buyer.example.invalid").get()
val buyerKeyFile = rootProject.file("key.properties")
val buyerSigning = Properties().apply {
    if (buyerKeyFile.isFile) buyerKeyFile.inputStream().use { load(it) }
}
val buyerReleaseSetup = tasks.register("validateBuyerReleaseSetup") {
    doLast {
        val required = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        require(buyerKeyFile.isFile && required.all {
            val value = buyerSigning.getProperty(it).orEmpty()
            value.isNotBlank() && !value.contains('<') && !value.contains('>')
        }) {
            "Configure owner release signing in ignored android/key.properties. See docs/release-setup.md."
        }
        val store = file(buyerSigning.getProperty("storeFile"))
        require(store.isFile && store.name != "debug.keystore" &&
            !buyerSigning.getProperty("keyAlias").equals("androiddebugkey", ignoreCase = true)) {
            "Use an existing owner release keystore, not the Android debug key."
        }
        require(buyerLinkHost.matches(Regex("^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$")) &&
            !buyerLinkHost.endsWith(".invalid") && !buyerLinkHost.endsWith(".test") &&
            !buyerLinkHost.endsWith(".localhost") &&
            listOf("example.com", "example.net", "example.org").none {
                buyerLinkHost == it || buyerLinkHost.endsWith(".$it")
            }) {
            "Configure the approved buyer link hostname. Use tool/buyer.dart to match the buyer origin."
        }
    }
}

android {
    namespace = "shop.bagooph.bagoo_buyer_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "shop.bagooph.bagoo_buyer_mobile"
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
        manifestPlaceholders["buyerLinkHost"] = buyerLinkHost
    }

    signingConfigs {
        create("release") {
            keyAlias = buyerSigning.getProperty("keyAlias")
            keyPassword = buyerSigning.getProperty("keyPassword")
            storePassword = buyerSigning.getProperty("storePassword")
            storeFile = buyerSigning.getProperty("storeFile")?.let { file(it) }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

tasks.configureEach {
    if (name.endsWith("Release") && listOf(
            "compileFlutterBuild", "package", "bundle", "assemble", "validateSigning"
        ).any { name.startsWith(it) }) {
        dependsOn(buyerReleaseSetup)
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
