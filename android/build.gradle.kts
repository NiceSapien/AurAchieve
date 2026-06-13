allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        val androidExtension = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (androidExtension != null) {
            val targetCompat = androidExtension.compileOptions.targetCompatibility
            if (targetCompat != null) {
                val jvmTargetValue = when (targetCompat.toString()) {
                    "1.8" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
                    "11" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
                    "17" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                    "21" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21
                    else -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                }
                compilerOptions.jvmTarget.set(jvmTargetValue)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}