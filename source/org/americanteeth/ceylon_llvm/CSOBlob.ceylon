import com.redhat.ceylon.model.typechecker.model {
    ModuleImport,
    Annotation
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
object blobKeys {
    shared Byte cls = 1.byte;
    shared Byte \iinterface = 2.byte;
    shared Byte attribute = 3.byte;
    shared Byte method = 4.byte;
    shared Byte \iobject = 5.byte;
    shared Byte \ialias = 6.byte;
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
class CSOBlob({Byte*} blobData = {}) {
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

    "Consume a single byte."
    shared Byte get() {
        "Must have a byte to get."
        assert(exists b = blob_[readPosition]);
        readPosition++;
        return b;
    }

    "Get an unsigned 64-bit integer stored in big endian format."
    shared Integer getUnsignedBigEndian64() {
        value bytes = blob_.spanFrom(readPosition).spanTo(8);
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

        value ret = CSOBlob(blob_.spanFrom(readPosition).spanTo(size));
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

    "Reset the read positiion."
    shared void rewind() {
        readPosition = 0;
    }

    "Size of this blob."
    shared Integer size => blob.size;
}
