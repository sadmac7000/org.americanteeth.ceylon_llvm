import org.americanteeth.ceylon_llvm {
    baremetalSupports
}

import com.redhat.ceylon.model.typechecker.model {
    BaseModule=Module,
    Class,
    NothingType,
    UnknownType,
    Unit
}

import ceylon.interop.java {
    CeylonList
}

import ceylon.collection {
    ArrayList
}

class Package() extends LazyPackage() {
    "A compilation unit for things that don't have one."
    value defaultUnit = Unit();

    "Type for unknown declarations."
    value unknownType = UnknownType(defaultUnit);

    "DeclarationData we've been given from the blob."
    value unpackedData = ArrayList<DeclarationData>();

    "Whether we've been loaded already."
    variable value loaded = false;

    "Module that we will load our data from."
    variable Module? sourceModule = null;

    "Unpack data from a blob into this package."
    shared void unpack(Blob data) {
        for ([a,b] in zipPairs(CeylonList(name), data.getStringList())) {
            "Package name must match blob data."
            assert(a.string == b.string);
        }

        \ishared = data.get() == 1.byte;

        while (exists d = data.getDeclarationData()) {
            unpackedData.add(d);
            defaultUnit.addDeclaration(d.declaration);
            addMember(d.declaration);
        }

        addMember(unknownType);
        unknownType.container = this;

        if (languagePackage) {
            value nothingType = object extends NothingType(defaultUnit) {
                shared actual Package container => outer;
            };

            defaultUnit.addDeclaration(nothingType);
            addMember(nothingType);
        }
    }

    shared actual BaseModule? \imodule => super.\imodule;
    assign \imodule {
        "Package should be assigned a source module only once."
        assert(! sourceModule exists);

        // Internal lookups fail if the language package is unavailable.
        if (exists m = \imodule, languagePackage) {
            m.available = true;
        }

        if (is Module \imodule,
            exists p = \imodule.getPackageData(nameAsString)) {
            sourceModule = \imodule;
            unpack(p);
        }

        defaultUnit.\ipackage = this;
        defaultUnit.filename = "";
        defaultUnit.fullPath = "";
        defaultUnit.relativePath = "";
        addUnit(defaultUnit);

        super.\imodule = \imodule;
    }

    "Load the data from Blob into the package's fields."
    shared actual void load() {
        value mod = sourceModule;

        if (! exists mod) {
            return;
        }

        if (loaded) {
            return;
        }

        loaded = true;

        for (d in unpackedData) {
            d.complete(mod, defaultUnit, this);
        }

        unpackedData.clear();
    }

    "Blob data serializing the metamodel for this package."
    shared Blob blob {
        value buf = Blob();
        buf.putStringList(name);
        buf.put(\ishared then 1.byte else 0.byte);

        for (m in iterableUnlessNull(members)) {
            if (is Class m, m.anonymous) {
                continue;
            }

            if (! baremetalSupports(m)) {
                continue;
            }

            buf.putDeclaration(m);
        }

        buf.put(0.byte);

        return buf;
    }
}
