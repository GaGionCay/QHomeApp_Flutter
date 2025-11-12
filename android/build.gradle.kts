allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val rootProjectBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(rootProjectBuildDir)

val rootDrive = rootProject.projectDir.toPath().root

subprojects {
    if (project.projectDir.toPath().root == rootDrive) {
        val newSubprojectBuildDir: Directory = rootProjectBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
