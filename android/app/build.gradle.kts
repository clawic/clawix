import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// --- Build identity from workspace-private files ----------------------------
//
// `applicationId` is opt-in via `local.properties#clawix.bundleId` (or env
// `CLAWIX_BUNDLE_ID`). Default is the placeholder so dev builds, the Android
// launcher script and external contributors keep working out of the box.
// Release pipelines (Play Console upload) set the real bundle id explicitly
// via env var at invocation time. The owner-private real bundle id lives in
// the workspace `.signing.env` (a sibling of the public `clawix/` repo) and
// is NEVER hardcoded inside the public repo.
//
// `versionName` reads `clawix/android/VERSION` (mirror of ios/VERSION,
// macos/VERSION) and `versionCode` reads `clawix/android/BUILD_NUMBER`
// (mirror of ios/BUILD_NUMBER). Both are NOT bumped automatically; only a
// release task should change them.

val clawixBundleId: String = run {
    val localProps = Properties().apply {
        val f = rootProject.file("local.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    localProps.getProperty("clawix.bundleId")
        ?: System.getenv("CLAWIX_BUNDLE_ID")
        ?: "com.example.clawix.android"
}

val clawixVersionName: String =
    rootProject.file("VERSION").takeIf { it.exists() }?.readText()?.trim().orEmpty()
        .ifBlank { "0.1.0" }

val clawixVersionCode: Int =
    rootProject.file("BUILD_NUMBER").takeIf { it.exists() }?.readText()?.trim()?.toIntOrNull()
        ?: 1

android {
    namespace = "com.example.clawix.android"
    compileSdk = 35

    defaultConfig {
        applicationId = clawixBundleId
        minSdk = 29
        targetSdk = 35
        versionCode = clawixVersionCode
        versionName = clawixVersionName

        vectorDrawables.useSupportLibrary = true
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            isDebuggable = true
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    kotlinOptions {
        jvmTarget = "21"
        freeCompilerArgs += listOf(
            "-opt-in=kotlinx.coroutines.ExperimentalCoroutinesApi",
            "-opt-in=kotlinx.coroutines.FlowPreview",
            "-opt-in=androidx.compose.material3.ExperimentalMaterial3Api",
            "-opt-in=androidx.compose.foundation.ExperimentalFoundationApi",
            "-opt-in=androidx.compose.animation.ExperimentalAnimationApi",
            "-opt-in=androidx.compose.ui.ExperimentalComposeUiApi",
        )
    }

    buildFeatures {
        compose = true
    }

    packaging {
        resources {
            excludes += setOf(
                "/META-INF/{AL2.0,LGPL2.1}",
                "/META-INF/INDEX.LIST",
                "/META-INF/io.netty.versions.properties",
            )
        }
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = false
            isReturnDefaultValues = true
        }
    }
}

dependencies {
    val composeBom = platform(libs.androidx.compose.bom)
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.core.splashscreen)
    implementation(libs.androidx.security.crypto)

    implementation(libs.mlkit.barcode)
    implementation(libs.camerax.core)
    implementation(libs.camerax.camera2)
    implementation(libs.camerax.lifecycle)
    implementation(libs.camerax.view)

    implementation(libs.okhttp)
    implementation(libs.coil.compose)

    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.datetime)

    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.kotlinx.serialization.json)
}
