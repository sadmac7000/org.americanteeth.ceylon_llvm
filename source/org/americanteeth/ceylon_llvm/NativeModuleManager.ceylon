import com.redhat.ceylon.model.typechecker.model {
    Module,
    ModuleImport
}

import com.redhat.ceylon.compiler.typechecker.analyzer {
    ModuleSourceMapper
}

import com.redhat.ceylon.compiler.typechecker.context {
    Context
}

import com.redhat.ceylon.model.typechecker.util {
    ModuleManager
}

import com.redhat.ceylon.common {
    Backend,
    Backends
}

import java.lang {
    JIterable = Iterable,
    JString = String
}

import java.util {
    JList = List
}

import ceylon.interop.java {
    JavaIterable,
    javaString
}

Backend backend = Backend.registerBackend("Bare Metal", "metal");

class NativeModuleSourceMapper(Context c, ModuleManager m)
        extends ModuleSourceMapper(c, m) {}

class NativeModuleManager() extends ModuleManager() {
    shared actual JIterable<JString> searchedArtifactExtensions
        => JavaIterable({javaString("src")});

    shared actual Backends supportedBackends => backend.asSet();

    shared actual Module createModule(JList<JString> modNameIn, String modVersion) {
        value mod = Module();
        mod.name = modNameIn;
        mod.version = modVersion;

        if (!(mod.nameAsString == Module.\iDEFAULT_MODULE_NAME
                || mod.nameAsString == Module.\iLANGUAGE_MODULE_NAME)) {

            value languageModule
                =   findLoadedModule(Module.\iLANGUAGE_MODULE_NAME, null)
                    else modules.languageModule;

            value moduleImport
                =   ModuleImport(languageModule, false, false);

            mod.addImport(moduleImport);
            mod.languageModule = languageModule;
        }
        return mod;
    }
}
