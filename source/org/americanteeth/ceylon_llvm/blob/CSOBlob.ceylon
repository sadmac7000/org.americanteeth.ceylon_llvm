import com.redhat.ceylon.model.typechecker.model {
    Declaration,
    Package,
    ModuleImport,
    Annotation,
    TypeDeclaration,
    Type,
    UnknownType,
    UnionType,
    IntersectionType
}

import com.redhat.ceylon.model.typechecker.util {
    ModuleManager
}

import ceylon.collection {
    ArrayList
}

import ceylon.buffer.charset {
    utf8
}

import java.util {
    JList=List
}

import java.lang {
    JString=String
}

import ceylon.interop.java {
    CeylonList,
    JavaList,
    javaString
}

"Marking bytes for differend serialized declarations."
shared object blobKeys {
    shared Byte \iclass = 1.byte;
    shared Byte \iinterface = 2.byte;
    shared Byte \ival = 3.byte;
    shared Byte \ifunction = 4.byte;
    shared Byte \iobject = 5.byte;
    shared Byte \ialias = 6.byte;
}

"Byte markers for standard types."
object typeKinds {
    "Type marker for a standard type."
    shared Byte plain = 1.byte;

    "Type marker for union types."
    shared Byte union = 2.byte;

    "Type marker for intersection types."
    shared Byte intersection = 3.byte;

    "Type marker for unknown types."
    shared Byte unknown = 4.byte;

    "Type marker for type parameters."
    shared Byte parameter = 5.byte;
}

"Flag bit indicating an import has the export annotation."
Byte exportFlag = 1.byte;

"Flag bit indicating an import is optional."
Byte optionalFlag = 2.byte;

"Byte marker for invariant type parameters."
Byte invariant = 0.byte;

"Byte marker for contravariant type parameters."
Byte contravariant = 1.byte;

"Byte marker for covariant type parameters."
Byte covariant = 2.byte;

"A consumable byte blob with some parsing helpers."
shared class CSOBlob({Byte*} blobData = {}) {
    value blob_ = ArrayList<Byte>{*blobData};

    "Our resulting blob data."
    shared {Byte*} blob = blob_;

    "Where reading starts from."
    variable Integer readPosition = 0;

    "Write a single byte."
    shared void put(Byte b) => blob_.add(b);

    "Write a string as utf8 and add a zero terminator."
    shared void putString(String s)
        => blob_.addAll(utf8.encode(s).chain{0.byte});

    "Write a list of zero-terminated utf8 strings, ending with an empty
     string."
    shared void putStringList({String*}|JList<JString> got) {
        {String*} s;

        if (! is {String*} got) {
            for (g in got) {}
            s = CeylonList(got).map(Object.string);
        } else {
            s = got;
        }

        blob_.addAll(s.map((x) => utf8.encode(x).chain{0.byte})
            .fold({} of {Byte*})((x,y) => x.chain(y)).chain{0.byte});
    }

    "Write an unsigned 64-bit integer in big endian."
    shared void putUnsignedBigEndian64(variable Integer val) {
        value bytes = ArrayList<Byte>();
        for (i in 1..8) {
            bytes.insert(0, val.byte);
            val = val.rightLogicalShift(8);
        }

        blob_.addAll(bytes);
    }

    "Write another blob into this blob, preceded by its size."
    shared void putSizedBlob(CSOBlob other) {
        putUnsignedBigEndian64(other.size);
        blob_.addAll(other.blob);
    }

    "Serialize and write a module import."
    shared void putModuleImport(ModuleImport imp) {
        variable Byte flag = 0.byte;

        if (imp.optional) {
            flag = flag.or(optionalFlag);
        }

        if (imp.export) {
            flag = flag.or(exportFlag);
        }

        putStringList(imp.\imodule.name);
        putString(imp.\imodule.version);
        put(flag);
    }

    "Serialize and write an annotation."
    shared void putAnnotation(Annotation ann) {
        putString(ann.name);
        putStringList(ann.positionalArguments);
    }

    "Serialize and write a type declaration."
    shared void putTypeDeclaration(TypeDeclaration t) {
        if (is UnknownType t) {
            put(typeKinds.unknown);
            return;
        }

        if (is UnionType t) {
            put(typeKinds.union);

            for (sub in t.caseTypes) {
                putType(sub);
            }

            put(0.byte);
            return;
        }

        if (is IntersectionType t) {
            put(typeKinds.intersection);

            for (sub in t.satisfiedTypes) {
                putType(sub);
            }

            put(0.byte);
            return;
        }

        put(typeKinds.plain);

        value name = ArrayList<String>();
        variable value pkg = t.container;

        while (! is Package p = pkg) {
            if (is Declaration p) {
                name.insert(0, p.name);
            }

            pkg = p.container;
        }

        "Loop should halt at a package."
        assert(is Package p = pkg);

        putStringList(p.name);
        name.add(t.name);
        putStringList(name);
    }

    "Serialize and write a type."
    shared void putType(Type t) {
        putTypeDeclaration(t.declaration);
        /* TODO: Type parameters. */
    }

    "Consume a single byte."
    shared Byte get() {
        "Must have a byte to get."
        assert(exists b = blob_[readPosition]);
        readPosition++;
        return b;
    }

    "Get an unsigned 64-bit integer stored in big endian format."
    shared Integer getUnsignedBigEndian64() {
        value bytes = blob_.spanFrom(readPosition).spanTo(7);
        readPosition += 8;

        variable value ret = 0;

        for (i in bytes) {
            ret = ret.leftLogicalShift(8);
            ret = ret.or(i.unsigned);
        }

        return ret;
    }

    "Get a sub-blob of this blob. Next read quantity is presumed to be its size
     as a 64-bit big-endian integer. If we read a zero we return null."
    shared CSOBlob? getSizedBlob() {
        value size = getUnsignedBigEndian64();

        if (size == 0) {
            return null;
        }

        value ret = CSOBlob(blob_.spanFrom(readPosition).spanTo(size-1));
        readPosition += size;
        return ret;
    }

    "Consume bytes up to but not including a byte where the given predicate
     returns true."
    List<Byte> getTo(Boolean(Byte) predicate) {
        value considered = blob_.spanFrom(readPosition);
        "Terminator not found."
        assert(exists split = considered.firstIndexWhere(predicate));

        value ret = considered.spanTo(split - 1);
        readPosition += split;
        return ret;
    }

    "Consume a string terminated by a low byte assumed to contain flag bits."
    shared String getString() {
        value ret = getTo((x) => x == 0.byte);
        get();
        return utf8.decode(ret);
    }

    "Consume a series of zero-terminated utf8 strings, ending with an empty
     string."
    shared List<String> getStringList() {
        value got = ArrayList<String>();

        while (true) {
            value term = getString();
            if (term.empty) {
                break;
            }

            got.add(term);
        }

        return got;
    }

    "Deserialize and return a ModuleImport. Returns null if we see an empty
     name field at the start of deserialization."
    shared ModuleImport? getModuleImport(ModuleManager moduleManager) {
        value name = getStringList();
        if (name.empty) {
            return null;
        }
        value jName = JavaList(name.collect(javaString));

        value version = getString();
        value flags = get();
        value optional = flags.and(optionalFlag) != 0.byte;
        value export = flags.and(exportFlag) != 0.byte;
        value mod = moduleManager.getOrCreateModule(jName, version);
        value backends = mod.nativeBackends;
        return ModuleImport(null, mod, optional, export, backends);
     }

    "Deserialize and return an Annotation. Returns null if we see an empty name
     field at the start of deserialization."
    shared Annotation? getAnnotation() {
        value name = getString();
        if (name.empty) {
            return null;
        }

        value annotation = Annotation();
        annotation.name = name;

        for (arg in getStringList()) {
            annotation.addPositionalArgument(arg);
        }

        return annotation;
     }

    "Deserialze and return data identifying a type declaration."
    shared TypeDeclarationData? getTypeDeclarationData() {
        value typeKind = get();

        if (typeKind == 0.byte) {
            return null;
        }

        if (typeKind == typeKinds.unknown) {
            return unknownTypeDeclarationData;
        }

        if (typeKind == typeKinds.union ||
            typeKind == typeKinds.intersection) {
            value types = ArrayList<TypeData>();

            while (exists t = getTypeData()) {
                types.add(t);
            }

            "Composite type should contain at least one type."
            assert(nonempty typeSequence = types.sequence());

            if (typeKind == typeKinds.union) {
                return UnionTypeDeclarationData(typeSequence);
            } else {
                return IntersectionTypeDeclarationData(typeSequence);
            }
        }

        if (typeKind == typeKinds.parameter) {
            return TypeParameterDeclarationData(getString());
        }

        "Byte should be a valid type kind indicatior."
        assert(typeKind == typeKinds.plain);

        value pkg = getStringList().sequence();
        value name = getStringList().sequence();

        "Package name should have at least one term."
        assert(nonempty pkg);

        "Type name should have at least one term."
        assert(nonempty name);

        return PlainTypeDeclarationData(pkg, name);
    }

    "Deserialize and return data identifying a type."
    shared TypeData? getTypeData() {
        if (exists t = getTypeDeclarationData()) {
            /* TODO: Type parameters */
            return TypeData(t);
        }

        return null;
    }

    "Reset the read positiion."
    shared void rewind() {
        readPosition = 0;
    }

    "Size of this blob."
    shared Integer size => blob.size;
}
