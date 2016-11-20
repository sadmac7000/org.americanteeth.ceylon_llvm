import com.redhat.ceylon.model.typechecker.model {
    Scope,
    BaseModule=Module,
    Declaration,
    Function,
    Value,
    Unit
}

import ceylon.interop.java {
    CeylonList
}

class Package() extends LazyPackage() {
    "Blob of binary data extracted from the module."
    variable Blob? blobData = null;

    "A compilation unit for things that don't have one."
    value defaultUnit = Unit();

    "Add a direct member we just loaded."
    void addLoadedMember(Declaration member) {
        defaultUnit.addDeclaration(member);
        addMember(member);
    }

    shared actual BaseModule? \imodule => super.\imodule;
    assign \imodule {
        if (is Module \imodule,
            exists p = \imodule.getPackageData(nameAsString)) {
            blobData = p;
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
        Blob data;

        if (exists d = blobData) {
            data = d;
            blobData = null;
        } else {
            return;
        }

        for ([a,b] in zipPairs(CeylonList(name), data.getStringList())) {
            "Package name must match blob data."
            assert(a.string == b.string);
        }

        \ishared = data.get() == 1.byte;

        while (loadDeclaration(data, this)) {}
    }

    "Load a declaration from the blob."
    Boolean loadDeclaration(Blob data, Scope parent) {
        value blobKey = data.get();
        assert(is Module mod = \imodule);

        if (blobKey == 0.byte) {
            return false;
        } else if (blobKey == blobKeys.\ifunction) {
            value f = data.getFunctionData();
            addLoadedMember(f.declaration);
            f.complete(mod, defaultUnit, this);
        } else if (blobKey == blobKeys.\ival) {
            value f = data.getValueData();
            addLoadedMember(f.declaration);
            f.complete(mod, defaultUnit, this);
        } else if (blobKey == blobKeys.\iinterface) {
            //loadInterface(data, parent);
        } else if (blobKey == blobKeys.\iclass) {
            //loadClass(data, parent);
        } else if (blobKey == blobKeys.\iobject) {
            //loadObject(data, parent);
        } else if (blobKey == blobKeys.\ialias) {
            //loadAlias(data, parent);
        } else {
            "Key byte should be a recognized value."
            assert(false);
        }

        return true;
    }

    "Write one member to the blob."
    void storeMember(Blob buf, Declaration d) {
        if (is Function d) {
            buf.put(blobKeys.\ifunction);
            buf.putFunctionOrValue(d);
        } else if (is Value d) {
            buf.put(blobKeys.\ival);
            buf.putFunctionOrValue(d);
        }

        /* TODO: Other declaration types */
    }

    "Blob data serializing the metamodel for this package."
    shared Blob blob {
        value buf = Blob();
        buf.putStringList(name);
        buf.put(\ishared then 1.byte else 0.byte);

        if (exists mem = members) {
            for (m in mem) {
                storeMember(buf, m);
            }
        }

        buf.put(0.byte);

        return buf;
    }
}
