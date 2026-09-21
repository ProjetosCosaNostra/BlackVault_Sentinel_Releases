plugins {
    id("com.android.application")
}

android {
    namespace = "br.com.lafamigliaplayworks.orcamentonoponto.preview"
    compileSdk = 36

    defaultConfig {
        applicationId = "br.com.lafamigliaplayworks.orcamentonoponto.preview"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "preview-1"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}


dependencies {
    implementation("androidx.core:core:1.17.0")
}
