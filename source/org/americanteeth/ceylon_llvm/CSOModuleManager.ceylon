import com.redhat.ceylon.model.typechecker.model {
    Module,
    Package,
    ModuleImport
}

import com.redhat.ceylon.compiler.typechecker.analyzer {
    ModuleSourceMapper
}

import com.redhat.ceylon.compiler.typechecker.context {
    Context,
    PhasedUnits
}

import com.redhat.ceylon.model.typechecker.util {
    ModuleManager
}

import com.redhat.ceylon.common {
    Backends
}

import java.lang {
    JIterable=Iterable,
    JString=String
}

import java.util {
    JList=List,
    JLinkedList=LinkedList
}

import ceylon.interop.java {
    JavaIterable,
    javaString
}

import com.redhat.ceylon.model.cmr {
    ArtifactResult
}

import ceylon.process {
    createProcess,
    currentOutput,
    currentError
}

import ceylon.file {
    parsePath,
    File
}

class CSOModuleSourceMapper(Context c, ModuleManager m)
        extends ModuleSourceMapper(c, m) {
    shared actual void resolveModule(ArtifactResult artifact, Module m,
            ModuleImport? moduleImport, JLinkedList<Module> dependencyTree,
            JList<PhasedUnits> phasedUnitsOfDependencies,
            Boolean forCompiledModule) {
        value modFile = artifact.artifact().absolutePath;

        if (modFile.endsWith(".src")) {
            super.resolveModule(artifact, m, moduleImport, dependencyTree,
                    phasedUnitsOfDependencies, forCompiledModule);
            return;
        }

        "CSOModuleSourceMapper should always get a CSOModule."
        assert(is CSOModule m);

        createProcess {
            command = "/usr/bin/objcopy";
            arguments = ["-O", "binary",
                "--only-section=ceylon.module",
                modFile,
                "/tmp/ceylon.module.tmpdata"];
            output=currentOutput;
            error=currentError;
        }.waitForExit();

        value file = parsePath("/tmp/ceylon.module.tmpdata").resource;

        "Objcopy should yield an output file"
        assert(is File file);

        m.loadFile(file);
    }
}

class CSOModuleManager() extends ModuleManager() {
    shared actual JIterable<JString> searchedArtifactExtensions
            => JavaIterable([ javaString("cso"),
                    javaString("src") ]);

    shared actual Backends supportedBackends => baremetalBackend.asSet();

    shared actual Module createModule(JList<JString> modNameIn,
            String modVersion) {
        value mod = CSOModule(this);
        mod.name = modNameIn;
        mod.version = modVersion;

        if (mod.nameAsString == Module.\iDEFAULT_MODULE_NAME) {
            return mod;
        }

        if (mod.nameAsString == Module.\iLANGUAGE_MODULE_NAME) {
            return mod;
        }

        value languageModule =
            findLoadedModule(Module.\iLANGUAGE_MODULE_NAME, null)
                    else modules.languageModule;

        value moduleImport = ModuleImport(null, languageModule, false, false);

        mod.addImport(moduleImport);
        mod.languageModule = languageModule;

        return mod;
    }

    shared actual Package createPackage(String pkgName, Module? mod) {
        if (exists mod, exists p = mod.getPackage(pkgName)) {
            return p;
        }

        value p = CSOPackage();
        p.name = ModuleManager.splitModuleName(pkgName);

        if (exists mod) {
            mod.packages.add(p);
            p.\imodule = mod;
        }

        return p;
    }
}
