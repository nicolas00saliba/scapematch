import groovy.json.JsonSlurper

// Um app por conta fantasma. Cada flavor tem applicationId próprio, então
// o Android guarda sessão, cookies e localStorage de cada um separados.
plugins {
    id("com.android.application")
}

@Suppress("UNCHECKED_CAST")
val config = JsonSlurper().parse(rootProject.file("../contas.json")) as Map<String, Any>
@Suppress("UNCHECKED_CAST")
val contas = config["contas"] as List<Map<String, Any>>

fun signing(name: String): String? = System.getenv(name)?.trim()?.takeIf { it.isNotEmpty() }

android {
    namespace = "br.com.escapematch.teste"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
        targetSdk = 36
        versionCode = (signing("APPS_FANTASMA_VERSION_CODE") ?: "1").toInt()
        versionName = "teste-" + (signing("APPS_FANTASMA_VERSION_CODE") ?: "1")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
        resValues = true
    }

    val storePath = signing("APPS_FANTASMA_KEYSTORE")
    if (storePath != null) {
        signingConfigs {
            create("teste") {
                storeFile = file(storePath)
                storePassword = signing("APPS_FANTASMA_STORE_PASSWORD")
                keyAlias = signing("APPS_FANTASMA_KEY_ALIAS") ?: "apps-fantasma"
                keyPassword = signing("APPS_FANTASMA_STORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = if (storePath != null) {
                signingConfigs.getByName("teste")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    flavorDimensions += "conta"
    productFlavors {
        for (conta in contas) {
            val slug = conta["slug"] as String
            val tipo = conta["tipo"] as String
            val numero = (conta["numero"] as Number).toInt()
            require(Regex("^[a-z]+[0-9]+$").matches(slug)) { "slug inválido: $slug" }
            require(tipo == "jogador" || tipo == "casa") { "tipo inválido: $tipo" }
            val url = config[if (tipo == "jogador") "jogador_url" else "casa_url"] as String
            val rotulo = (if (tipo == "jogador") "EM Jogador " else "EM Casa ") + numero
            val selo = (if (tipo == "jogador") "JOGADOR " else "CASA ") + numero
            val cor = if (tipo == "jogador") "#1E88E5" else "#E65100"
            create(slug) {
                dimension = "conta"
                applicationId = "br.com.escapematch.teste.$slug"
                resValue("string", "app_name", rotulo)
                buildConfigField("String", "START_URL", "\"$url\"")
                buildConfigField("String", "BADGE", "\"$selo\"")
                buildConfigField("String", "BADGE_COLOR", "\"$cor\"")
                buildConfigField("String", "SLUG", "\"$slug\"")
            }
        }
    }
}
