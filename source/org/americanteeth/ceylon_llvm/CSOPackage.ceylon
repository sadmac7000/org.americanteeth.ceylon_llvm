import com.redhat.ceylon.model.typechecker.model {
    Scope,
    Module,
    Declaration,
    Function,
    Value,
    Unit
}

import ceylon.interop.java {
    CeylonList
}

import org.americanteeth.ceylon_llvm.blob {
    CSOBlob,
    blobKeys
}

shared class CSOPackage() extends LazyPackage() {
    "Blob of binary data extracted from the module."
    variable CSOBlob? blobData = null;

    "A compilation unit for things that don't have one."
    value defaultUnit = Unit();

    "Add a direct member we just loaded."
    void addLoadedMember(Declaration member) {
        defaultUnit.addDeclaration(member);
        addMember(member);
    }

    shared actual Module? \imodule => super.\imodule;
    assign \imodule {
        if (is CSOModule \imodule,
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

    "Load the data from CSOBlob into the package's fields."
    shared actual void load() {
        CSOBlob data;

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
    Boolean loadDeclaration(CSOBlob data, Scope parent) {
        value blobKey = data.get();
        assert(is CSOModule mod = \imodule);

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
    void storeMember(CSOBlob buf, Declaration d) {
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
    shared CSOBlob blob {
        value buf = CSOBlob();
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
