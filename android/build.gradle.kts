allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val sharedBuildDirectory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(sharedBuildDirectory)
subprojects {
    layout.buildDirectory.value(sharedBuildDirectory.dir(project.name))
    evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
