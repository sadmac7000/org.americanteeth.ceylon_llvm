import org.americanteeth.ceylon_llvm {
    baremetalBackend
}

import org.eclipse.ceylon.model.typechecker.model {
    BaseModule=Module,
    BasePackage=Package,
    ModuleImport
}

import org.eclipse.ceylon.compiler.typechecker.analyzer {
    BaseModuleSourceMapper=ModuleSourceMapper
}

import org.eclipse.ceylon.compiler.typechecker.context {
    Context,
    PhasedUnits
}

import org.eclipse.ceylon.model.typechecker.util {
    BaseModuleManager=ModuleManager
}

import org.eclipse.ceylon.compiler.typechecker.util {
    ModuleManagerFactory
}
import org.eclipse.ceylon.common {
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

import org.eclipse.ceylon.model.cmr {
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

class ModuleSourceMapper(Context c, BaseModuleManager m)
        extends BaseModuleSourceMapper(c, m) {
    shared actual void resolveModule(ArtifactResult artifact, BaseModule m,
            ModuleImport? moduleImport, JLinkedList<BaseModule> dependencyTree,
            JList<PhasedUnits> phasedUnitsOfDependencies,
            Boolean forCompiledModule) {
        value modFile = artifact.artifact().absolutePath;

        if (modFile.endsWith(".src")) {
            super.resolveModule(artifact, m, moduleImport, dependencyTree,
                    phasedUnitsOfDependencies, forCompiledModule);
            return;
        }

        "ModuleSourceMapper should always get a cso.Module."
        assert(is Module m);

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

class ModuleManager() extends BaseModuleManager() {
    shared actual JIterable<JString> searchedArtifactExtensions
            => JavaIterable([ javaString("cso") ]);

    shared actual Backends supportedBackends => baremetalBackend.asSet();

    shared actual Module createModule(JList<JString> modNameIn,
            String modVersion) {
        value mod = Module(this);
        mod.name = modNameIn;
        mod.version = modVersion;

        if (mod.nameAsString == BaseModule.\iDEFAULT_MODULE_NAME) {
            return mod;
        }

        if (mod.nameAsString == BaseModule.\iLANGUAGE_MODULE_NAME) {
            return mod;
        }

        value languageModule =
            findLoadedModule(BaseModule.\iLANGUAGE_MODULE_NAME, null)
                    else modules.languageModule;

        value moduleImport = ModuleImport(null, languageModule, false, false);

        mod.addImport(moduleImport);
        mod.languageModule = languageModule;

        return mod;
    }

    shared actual BasePackage createPackage(String pkgName, BaseModule? mod) {
        if (exists mod, exists p = mod.getPackage(pkgName)) {
            return p;
        }

        value p = Package();
        p.name = BaseModuleManager.splitModuleName(pkgName);

        if (exists mod) {
            mod.packages.add(p);
            p.\imodule = mod;
        }

        return p;
    }
}

shared object moduleManagerFactory satisfies ModuleManagerFactory {
    shared actual BaseModuleManager createModuleManager(Context c)
        => ModuleManager();
    shared actual BaseModuleSourceMapper createModuleManagerUtil(Context c,
            BaseModuleManager m)
        => ModuleSourceMapper(c, m);
}
