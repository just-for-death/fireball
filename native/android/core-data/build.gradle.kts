plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.fireball.nativeapp.core.data"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    lint {
        disable += setOf(
            /** See :app — Ktor stays on 2.3.x until a dedicated Ktor 3 migration. */
            "GradleDependency",
            "NewerVersionAvailable",
        )
    }
}

dependencies {
    implementation(project(":core-model"))

    implementation("com.github.TeamNewPipe:NewPipeExtractor:v0.26.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    implementation("io.ktor:ktor-client-core:2.3.13")
    implementation("io.ktor:ktor-client-okhttp:2.3.13")
    implementation("io.ktor:ktor-client-content-negotiation:2.3.13")
    implementation("io.ktor:ktor-serialization-kotlinx-json:2.3.13")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")
}
