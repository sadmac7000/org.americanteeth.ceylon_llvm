import com.redhat.ceylon.common {
    Backends
}

import com.redhat.ceylon.model.typechecker.model {
    Package,
    Module
}

import ceylon.file {
    File
}

import ceylon.collection {
    HashMap,
    HashSet
}

import ceylon.interop.java {
    CeylonList,
    JavaList,
    javaString
}

import com.redhat.ceylon.model.typechecker.util {
    ModuleManager
}

import org.americanteeth.ceylon_llvm.blob {
    CSOBlob,
    loadModuleAnnotations,
    storeModuleAnnotations
}
"ABI version number"
Byte abiVersion = 0.byte;

class CSOModule(ModuleManager moduleManager) extends Module() {
    "Package data from the loaded module."
    value packageData = HashMap<String, CSOBlob>();

    "Get package data for a given package."
    shared CSOBlob? getPackageData(String name) => packageData[name];

    "Given a .cso file object, fetch our metamodel data."
    shared void loadFile(File file) {
        Byte[] blobData;

        try (r = file.Reader()) {
            blobData = r.readBytes(file.size);
        }

        "Read should yield entire blob."
        assert(blobData.size == file.size);

        value blob = CSOBlob(blobData);

        "ABI version must match."
        assert(blob.get() == abiVersion);

        value gotVersion = blob.getString();
        value nativeBit = blob.get();

        nativeBackends =
            if (nativeBit == 0.byte)
            then Backends.\iANY
            else baremetalBackend.asSet();

        "Module versions must match."
        assert(version == gotVersion);

        value gotName = blob.getStringList();

        for ([a,b] in zipPairs(CeylonList(name), gotName)) {
            "Module name must match blob data."
            assert(a.string == b.string);
        }

        while (exists imp = blob.getModuleImport(moduleManager)) {
            addImport(imp);
        }

        loadModuleAnnotations(blob, this);

        while (exists data = blob.getSizedBlob()) {
            value name = data.getStringList();
            value nameString = ".".join(name);
            data.rewind();
            packageData.put(nameString, data);
            value pkg = CSOPackage();
            pkg.name = JavaList(name.collect(javaString));
            pkg.\imodule = this;
            packages.add(pkg);
        }
    }

    "Binary encoding of module meta-data"
    shared {Byte*} binData {
        value buf = CSOBlob();

        buf.put(abiVersion);
        buf.putString(version);
        buf.put(nativeBackends == Backends.\iANY then 1.byte else 0.byte);
        buf.putStringList(name);

        CeylonList(imports).each(buf.putModuleImport);
        buf.putStringList([]);

        storeModuleAnnotations(buf, this);

        for (pkg in packages) {
            "CSOModule should have only CSOPackage children."
            assert(is CSOPackage pkg);
            buf.putSizedBlob(pkg.blob);
        }

        return buf.blob;
    }

    "The default implementation doesn't check exported modules."
    shared actual Package? getPackage(String name) {
        value visited = HashSet<Module>();

        Package? visit(Module m) {
            if (visited.contains(m)) {
                return null;
            }

            visited.add(m);

            if (exists p = m.getDirectPackage(name)) {
                return p;
            }

            for (imp in m.imports) {
                if (imp.export || m == this,
                    exists p = visit(imp.\imodule)) {
                    return p;
                }
            }

            return null;
        }

        return visit(this);
    }
}
