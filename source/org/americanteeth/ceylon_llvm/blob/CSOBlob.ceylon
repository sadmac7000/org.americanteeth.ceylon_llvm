import com.redhat.ceylon.model.typechecker.model {
    Annotation,
    Class,
    Constructor,
    Declaration,
    Function,
    FunctionOrValue,
    IntersectionType,
    ModuleImport,
    Package,
    Parameter,
    ParameterList,
    Type,
    TypeDeclaration,
    UnionType,
    UnknownType,
    Value
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

"Byte marking the start of a parameter list."
Byte startOfParameters = #ff.byte;

"Flags for parameters."
object parameterFlags {
    "Flag bit indicating a parameter is sequenced."
    shared Byte sequenced = 1.byte;

    "Flag bit indicating a parameter is defaulted."
    shared Byte defaulted = 2.byte;

    "Flag bit indicating a parameter needs at least one argument."
    shared Byte atLeastOne = 4.byte;

    "Flag bit indicating a parameter is hidden."
    shared Byte hidden = 8.byte;

    "Flag bit indicating a parameter has parameter lists of its own."
    shared Byte functionParameter = 16.byte;
}

"Flags for functions."
object functionFlags {
    "Flag indicating a function was declared void."
    shared Byte \ivoid = 1.byte;

    "Flag indicating a function was deferred."
    shared Byte deferred = 2.byte;
}

"Flags for values."
object valueFlags {
    "Flag indicating a value is transient."
    shared Byte transient = 1.byte;

    "Flag indicating a value is static."
    shared Byte static = 2.byte;

    "Flag indicating a value has a setter."
    shared Byte hasSetter = 4.byte;

    "Flag indicating a value is variable."
    shared Byte \ivariable = 8.byte;
}

"First byte of packed annotation flags."
object packedAnnotations1 {
    "Flag for the shared annotation."
    shared Byte \ishared = 1.byte;

    "Flag for the actual annotation."
    shared Byte \iactual = 2.byte;

    "Flag for the formal annotation."
    shared Byte \iformal = 4.byte;

    "Flag for the default annotation."
    shared Byte \idefault = 8.byte;

    "Flag for the native annotation."
    shared Byte \inative = 16.byte;

    "Flag for the annotation annotation."
    shared Byte \iannotation = 32.byte;

    "Flag for the sealed annotation."
    shared Byte \isealed = 64.byte;

    "Flag for the final annotation."
    shared Byte \ifinal = 128.byte;
}

"Second byte of packed annotation flags."
object packedAnnotations2 {
    "Flag for the abstract annotation."
    shared Byte \iabstract = 1.byte;

    "Flag for the late annotation."
    shared Byte \ilate = 2.byte;

    "Flag for the variable annotation."
    shared Byte \ivariable = 4.byte;
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

    "Put the annotations for a declaration to the blob."
    shared void putAnnotations(Declaration d) {
        variable value packed1 = 0.byte;
        variable value packed2 = 0.byte;

        if (d.\ishared) {
            packed1 = packed1.or(packedAnnotations1.\ishared);
        }

        if (d.\iactual) {
            packed1 = packed1.or(packedAnnotations1.\iactual);
        }

        if (d.\iformal) {
            packed1 = packed1.or(packedAnnotations1.\iformal);
        }

        if (d.\idefault) {
            packed1 = packed1.or(packedAnnotations1.\idefault);
        }

        /* TODO: Native? */

        if (d.\iannotation) {
            packed1 = packed1.or(packedAnnotations1.\iannotation);
        }

        if (is Class d, d.\ifinal) {
            packed1 = packed1.or(packedAnnotations1.\ifinal);
        }

        if (is Class|Constructor d, d.\iabstract) {
            packed2 = packed2.or(packedAnnotations2.\iabstract);
        }

        if (is Value d, d.\ilate) {
            packed2 = packed2.or(packedAnnotations2.\ilate);
        }

        if (is Value d, d.\ivariable) {
            packed2 = packed2.or(packedAnnotations2.\ivariable);
        }

        put(packed1);
        put(packed2);

        for (ann in d.annotations) {
            putAnnotation(ann);
        }

        put(0.byte);
    }

    "Serialize and write a Function or Value."
    shared void putFunctionOrValue(FunctionOrValue f) {
        putString(f.name);

        putAnnotations(f);

        putType(f.type);

        variable value flags = 0.byte;

        if (is Function f) {
            if (f.declaredVoid) {
                flags = flags.or(functionFlags.\ivoid);
            }

            if (f.deferred) {
                flags = flags.or(functionFlags.deferred);
            }
        } else {
            assert(is Value f);

            if (f.transient) {
                flags = flags.or(valueFlags.transient);
            }

            if (f.\ivariable) {
                flags = flags.or(valueFlags.\ivariable);
            }

            if (f.staticallyImportable) {
                flags = flags.or(valueFlags.static);
            }

            if (f.setter exists) {
                flags = flags.or(valueFlags.hasSetter);
            }
        }

        put(flags);

        if (is Value f, exists s = f.setter) {
            putAnnotations(s);
        }

        /* TODO: Type parameters. */

        if (is Value f) {
            return;
        }

        assert(is Function f);

        for (p in f.parameterLists) {
            putParameterList(p);
        }

        put(0.byte);
    }

    "Serialize and write a parameter list."
    shared void putParameterList(ParameterList p) {
        put(startOfParameters);

        for (param in p.parameters) {
            putParameter(param);
        }

        put(0.byte);
    }

    "Serialize and write a parameter."
    shared void putParameter(Parameter param) {
        putString(param.name);

        variable value flags = 0.byte;

        if (param.hidden) {
            flags = flags.or(parameterFlags.hidden);
        }

        if (param.defaulted) {
            flags = flags.or(parameterFlags.defaulted);
        }

        if (param.sequenced) {
            flags = flags.or(parameterFlags.sequenced);
        }

        if (param.atLeastOne) {
            flags = flags.or(parameterFlags.atLeastOne);
        }

        value model = param.model;

        if (is Function model) {
            flags = flags.or(parameterFlags.functionParameter);
            put(flags);

            for (plist in model.parameterLists) {
                putParameterList(plist);
            }

            put(0.byte);
        } else {
            put(flags);
        }

        putType(model.type);

        putAnnotations(model);
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

    "Read the annotations for a declaration from a blob."
    shared AnnotationData getAnnotationData() {
        variable value packed1 = get();
        variable value packed2 = get();

        value \ishared = packed1.and(packedAnnotations1.\ishared) != 0.byte;
        value \iactual = packed1.and(packedAnnotations1.\iactual) != 0.byte;
        value \iformal = packed1.and(packedAnnotations1.\iformal) != 0.byte;
        value \idefault = packed1.and(packedAnnotations1.\idefault) != 0.byte;
        value \inative = packed1.and(packedAnnotations1.\inative) != 0.byte;
        value \iannotation = packed1.and(packedAnnotations1.\iannotation)
            != 0.byte;
        value \ifinal = packed1.and(packedAnnotations1.\ifinal) != 0.byte;
        value \iabstract = packed2.and(packedAnnotations2.\iabstract) != 0.byte;
        value \ilate = packed2.and(packedAnnotations2.\ilate) != 0.byte;
        value \ivariable = packed2.and(packedAnnotations2.\ivariable) != 0.byte;

        value annotations = ArrayList<Annotation>();
        while (exists ann = getAnnotation()) {
            annotations.add(ann);
        }

        return AnnotationData(\ishared, \iactual, \iformal, \idefault,
                \inative, \ifinal, \iabstract, \iannotation, \ilate,
                \ivariable, annotations.sequence());
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

    "Deserialize and return data indicating a parameter list."
    ParameterListData? getParameterListData() {
        if (get() != startOfParameters) {
            return null;
        }

        value params = ArrayList<ParameterData>();
        while (exists param = getParameterData()) {
            params.add(param);
        }

        return ParameterListData(params.sequence());
    }

    "Load a parameter from the blob."
    ParameterData? getParameterData() {
        value name = getString();

        if (name.empty) {
            return null;
        }

        value flags = get();

        value hidden = flags.and(parameterFlags.hidden) != 0.byte;
        value defaulted = flags.and(parameterFlags.defaulted) != 0.byte;
        value sequenced = flags.and(parameterFlags.sequenced) != 0.byte;
        value atLeastOne = flags.and(parameterFlags.atLeastOne) != 0.byte;

        value parameterType = if (! sequenced)
            then ParameterType.normal
            else if (atLeastOne)
            then ParameterType.oneOrMore
            else ParameterType.zeroOrMore;

        value parameterLists = ArrayList<ParameterListData>();

        if (flags.and(parameterFlags.functionParameter) != 0.byte) {
            while (exists p = getParameterListData()) {
                parameterLists.add(p);
            }
        }

        "Parameter should have a type."
        assert(exists type = getTypeData ());
        value annotations  = getAnnotationData();

        return ParameterData(name, hidden, defaulted, parameterType,
                parameterLists.sequence(), type, annotations);
    }


    "Deserialize return data identifying a function."
    shared FunctionData getFunctionData() {
        value name = getString();
        value annotations = getAnnotationData();
        value type = getTypeData();
        value flags = get();
        value declaredVoid = flags.and(functionFlags.\ivoid) != 0.byte;
        value deferred = flags.and(functionFlags.deferred) != 0.byte;

        value parameterLists = ArrayList<ParameterListData>();
        while (exists p = getParameterListData()) {
            parameterLists.add(p);
        }

        "Function should have at least one parameter list."
        assert(nonempty parameterSequence = parameterLists.sequence());

        return FunctionData(name, type, annotations, declaredVoid, deferred,
                parameterSequence);
    }

    "Deserialize return data identifying a value."
    shared ValueData getValueData() {
        value name = getString();
        value annotations = getAnnotationData();

        "Value must have a type."
        assert(exists type = getTypeData());
        value flags = get();
        value transient = flags.and(valueFlags.transient) != 0.byte;
        value staticallyImportable = flags.and(valueFlags.static) != 0.byte;
        value \ivariable = flags.and(valueFlags.\ivariable) != 0.byte;

        value setterAnnotations =
            if (flags.and(valueFlags.hasSetter) != 0.byte)
            then getAnnotationData()
            else null;

        return ValueData(name, type, annotations, transient,
                staticallyImportable, \ivariable, setterAnnotations);
    }

    "Reset the read positiion."
    shared void rewind() {
        readPosition = 0;
    }

    "Size of this blob."
    shared Integer size => blob.size;
}
