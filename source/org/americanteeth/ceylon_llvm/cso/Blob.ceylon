import com.redhat.ceylon.model.typechecker.model {
    Annotation,
    Class,
    ClassAlias,
    ClassOrInterface,
    Constructor,
    Declaration,
    Function,
    FunctionOrValue,
    Interface,
    InterfaceAlias,
    IntersectionType,
    ModuleImport,
    Package,
    Parameter,
    ParameterList,
    Setter,
    SiteVariance,
    Type,
    TypeAlias,
    TypeDeclaration,
    TypeParameter,
    UnionType,
    UnknownType,
    Value
}

import com.redhat.ceylon.model.typechecker.util {
    ModuleManager
}

import ceylon.collection {
    ArrayList,
    HashMap,
    HashSet
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
    CeylonMap,
    JavaList,
    javaString
}

import org.americanteeth.ceylon_llvm {
    baremetalSupports
}

"Get a Ceylon iterable from a Java list, or an empty iterable if given null."
{T*} iterableUnlessNull<T>(JList<T>? l)
        given T satisfies Object
    => if (exists l) then CeylonList(l) else [];

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

    "Flag indicating a value is anonymous."
    shared Byte anonymous = 16.byte;
}

"Flags for classes."
object classFlags {
    "Whether this class is an alias for another class."
    shared Byte \ialias = 1.byte;

    "Whether this class is an alias that specifies a named constructor."
    shared Byte constructedAlias = 2.byte;

    "Whether this class is abstract."
    shared Byte \iabstract = 4.byte;

    "Whether this is an anonymous class."
    shared Byte anonymous = 8.byte;

    "Whether this class is static."
    shared Byte static = 16.byte;
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
object blobKeys {
    shared Byte \iclass = 1.byte;
    shared Byte \iinterface = 2.byte;
    shared Byte \ival = 3.byte;
    shared Byte \ifunction = 4.byte;
    shared Byte \ialias = 5.byte;
    shared Byte constructor = 6.byte;
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

"Flags for module imports"
object importFlags {
    "Flag bit indicating an import has the export annotation."
    shared Byte exportFlag = 1.byte;

    "Flag bit indicating an import is optional."
    shared Byte optionalFlag = 2.byte;
}

"Byte marker for variances."
object variances {
    "Byte marker for contravariant type parameters."
    shared Byte contravariant = 1.byte;

    "Byte marker for covariant type parameters."
    shared Byte covariant = 2.byte;

    "Byte marker for invariant type parameters."
    shared Byte invariant = 3.byte;
}

"A consumable byte blob with some parsing helpers."
class Blob({Byte*} blobData = {}) {
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
    shared void putSizedBlob(Blob other) {
        putUnsignedBigEndian64(other.size);
        blob_.addAll(other.blob);
    }

    "Serialize and write a module import."
    shared void putModuleImport(ModuleImport imp) {
        variable Byte flag = 0.byte;

        if (imp.optional) {
            flag = flag.or(importFlags.optionalFlag);
        }

        if (imp.export) {
            flag = flag.or(importFlags.exportFlag);
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

        for (parameter -> type in CeylonMap(t.typeArguments)) {
            value variance = switch(t.varianceOverrides?.get(parameter))
                case (SiteVariance.\iIN) variances.contravariant
                case (SiteVariance.\iOUT) variances.covariant
                else variances.invariant;
            value name =
                "``partiallyQualifiedName(t.declaration)``.``parameter.name``";
            putType(type);
            putString(name);
            put(variance);
        }

        put(0.byte);
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

        if (d.\inative) {
            packed1 = packed1.or(packedAnnotations1.\inative);
        }

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

    "Serialize and write case and satisfied types for a generic."
    shared void putSatisfiedAndCaseTypes(TypeDeclaration g) {
        for (satisfiedType in iterableUnlessNull(g.satisfiedTypes)) {
            putType(satisfiedType);
        }
        put(0.byte);

        for (caseType in iterableUnlessNull(g.caseTypes)) {
            putType(caseType);
        }
        put(0.byte);
    }

    "Serialize and write a type parameter."
    shared void putTypeParameter(TypeParameter p) {
        if (p.covariant) {
            put(variances.covariant);
        } else if (p.contravariant) {
            put(variances.contravariant);
        } else {
            put(variances.invariant);
        }

        putString(p.name);

        if (exists d = p.defaultTypeArgument) {
            putType(d);
        } else {
            put(0.byte);
        }

        if (exists d = p.extendedType) {
            putType(d);
        } else {
            put(0.byte);
        }

        putSatisfiedAndCaseTypes(p);
    }

    "Serialize and write a Function or Value."
    shared void putFunctionOrValue(FunctionOrValue f) {
        putString(f.name);

        putAnnotations(f);

        variable value flags = 0.byte;
        Class? anonymousClass;

        if (is Function f) {
            anonymousClass = null;

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

            if (f.static) {
                flags = flags.or(valueFlags.static);
            }

            if (f.setter exists) {
                flags = flags.or(valueFlags.hasSetter);
            }

            if (is Class c = f.type?.declaration, c.anonymous) {
                flags = flags.or(valueFlags.anonymous);
                anonymousClass = c;
            } else {
                anonymousClass = null;
            }
        }

        put(flags);
        if (exists anonymousClass) {
            putClassOrInterface(anonymousClass);
        } else {
            putType(f.type);
        }

        if (is Value f, exists s = f.setter) {
            putAnnotations(s);
        }

        if (is Value f) {
            return;
        }

        assert(is Function f);

        for (p in iterableUnlessNull(f.typeParameters)) {
            putTypeParameter(p);
        }

        put(0.byte);

        for (p in f.parameterLists) {
            putParameterList(p);
        }

        put(0.byte);
    }

    "Serialize and write a type alias."
    shared void putTypeAlias(TypeAlias ta) {
        putString(ta.name);
        putAnnotations(ta);

        for (p in iterableUnlessNull(ta.typeParameters)) {
            putTypeParameter(p);
        }

        put(0.byte);

        putType(ta.extendedType);
        putSatisfiedAndCaseTypes(ta);
    }

    "Serialize and write a class."
    shared void putClassOrInterface(ClassOrInterface cls) {
        putString(cls.name);
        putAnnotations(cls);

        String? aliasName;

        variable value flags = 0.byte;

        if (is Class cls) {
            if (cls.\iabstract) {
                flags = flags.or(classFlags.\iabstract);
            }

            if (cls.anonymous) {
                flags = flags.or(classFlags.anonymous);
            }

            if (cls.static) {
                flags = flags.or(classFlags.static);
            }
        } else if (is InterfaceAlias cls){
            flags = 1.byte;
        }

        if (is ClassAlias cls) {
            flags = flags.or(classFlags.\ialias);

            if (cls.constructor != cls.extendedType.declaration) {
                flags = flags.or(classFlags.constructedAlias);
                aliasName = cls.constructor.name;
            } else {
                aliasName = null;
            }
        } else {
            aliasName = null;
        }

        put(flags);

        if (exists aliasName) {
            putString(aliasName);
        }

        for (p in iterableUnlessNull(cls.typeParameters)) {
            putTypeParameter(p);
        }

        put(0.byte);

        if (is Class cls) {
            if (exists parameterList = cls.parameterList) {
                putParameterList(parameterList);
            } else {
                put(0.byte);
            }
        }

        if (exists t = cls.extendedType) {
            putType(t);
        } else {
            put(0.byte);
        }

        putSatisfiedAndCaseTypes(cls);

        value constructorNames = HashSet<String>();

        for (member in cls.members) {
            if (is Constructor member, exists n = member.name) {
                constructorNames.add(n);
            }
        }

        for (member in cls.members) {
            if (! baremetalSupports(member)) {
                continue;
            }

            if (is Class member, member.anonymous) {
                continue;
            }

            if (is TypeParameter|Setter member) {
                continue;
            }

            if (is Constructor member) {
                putDeclaration(member);
                continue;
            }

            value n = member.name;

            if (! exists n) {
                continue;
            }

            if (n in constructorNames) {
                continue;
            }

            putDeclaration(member);
        }
        put(0.byte);
    }

    "Serialize and write a constructor."
    shared void putConstructor(Constructor c) {
        putString(c.name else "");
        putAnnotations(c);

        if (exists p = c.parameterList) {
            putParameterList(p);
        } else {
            put(0.byte);
        }
    }

    "Write one member to the blob."
    shared void putDeclaration(Declaration d) {
        if (is Function d) {
            put(blobKeys.\ifunction);
            putFunctionOrValue(d);
        } else if (is Value d) {
            put(blobKeys.\ival);
            putFunctionOrValue(d);
        } else if (is Class d) {
            put(blobKeys.\iclass);
            putClassOrInterface(d);
        } else if (is Interface d) {
            put(blobKeys.\iinterface);
            putClassOrInterface(d);
        } else if (is TypeAlias d) {
            put(blobKeys.\ialias);
            putTypeAlias(d);
        } else if (is Constructor d) {
            put(blobKeys.constructor);
            putConstructor(d);
        } else {
            "Declaration should be of a known type."
            assert(false);
        }
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
    shared Blob? getSizedBlob() {
        value size = getUnsignedBigEndian64();

        if (size == 0) {
            return null;
        }

        value ret = Blob(blob_.spanFrom(readPosition).spanTo(size-1));
        readPosition += size;
        return ret;
    }

    "Consume a string terminated by a low byte assumed to contain flag bits."
    shared String getString() {
        variable value length = 0;
        value start = readPosition;
        while (exists b = blob_[readPosition + length++], b != 0.byte) {}
        readPosition += length;
        return utf8.decode(blob_[start:length-1]);
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
        value optional = flags.and(importFlags.optionalFlag) != 0.byte;
        value export = flags.and(importFlags.exportFlag) != 0.byte;
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
        value t = getTypeDeclarationData();

        if (! exists t) {
            return null;
        }

        value arguments = HashMap<String,TypeArgumentData>();

        while (exists type = getTypeData()) {
            value name = getString();

            "Type parameter should have a variance."
            assert(exists variance = getVariance());

            arguments[name] = TypeArgumentData(variance, type);
        }

        return TypeData(t, if (arguments.empty) then null else arguments);
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

    shared Variance? getVariance() {
        value varianceByte = get();

        return if (varianceByte == variances.contravariant)
                then Variance.contravariant
            else if (varianceByte == variances.covariant)
                then Variance.covariant
            else if (varianceByte == variances.invariant)
                then Variance.invariant
            else null;
    }

    shared [{TypeData*}, {TypeData*}] getCaseAndSatisfiedTypes() {
        value satisfiedTypes = ArrayList<TypeData>();
        value caseTypes = ArrayList<TypeData>();

        while (exists t = getTypeData()) {
            satisfiedTypes.add(t);
        }

        while (exists t = getTypeData()) {
            caseTypes.add(t);
        }

        return [satisfiedTypes, caseTypes];
    }

    shared TypeParameterData? getTypeParameterData() {
        value variance = getVariance();

        if (! exists variance) {
            return null;
        }

        value name = getString();
        value defaultType = getTypeData();
        value extendedType = getTypeData();

        value [satisfiedTypes, caseTypes] = getCaseAndSatisfiedTypes();

        return TypeParameterData(name, variance, defaultType, extendedType,
            satisfiedTypes, caseTypes);
    }

    shared [TypeParameterData*] getTypeParametersData() {
        value accum = ArrayList<TypeParameterData>();

        while (exists p = getTypeParameterData()) {
            accum.add(p);
        }

        return accum.sequence();
    }

    "Deserialize return data identifying a function."
    shared FunctionData getFunctionData() {
        value name = getString();
        value annotations = getAnnotationData();
        value flags = get();
        value type = getTypeData();
        value declaredVoid = flags.and(functionFlags.\ivoid) != 0.byte;
        value deferred = flags.and(functionFlags.deferred) != 0.byte;
        value typeParameters = getTypeParametersData();

        value parameterLists = ArrayList<ParameterListData>();
        while (exists p = getParameterListData()) {
            parameterLists.add(p);
        }

        "Function should have at least one parameter list."
        assert(nonempty parameterSequence = parameterLists.sequence());

        return FunctionData(name, type, annotations, typeParameters,
                declaredVoid, deferred, parameterSequence);
    }

    "Deserialize and return data identifying a value."
    shared ValueData getValueData() {
        value name = getString();
        value annotations = getAnnotationData();

        value flags = get();
        value transient = flags.and(valueFlags.transient) != 0.byte;
        value static = flags.and(valueFlags.static) != 0.byte;
        value \ivariable = flags.and(valueFlags.\ivariable) != 0.byte;
        value anonymous = flags.and(valueFlags.anonymous) != 0.byte;

        "Value must have a type."
        assert(exists type = if (anonymous)
                then getClassData()
                else getTypeData());

        value setterAnnotations =
            if (flags.and(valueFlags.hasSetter) != 0.byte)
            then getAnnotationData()
            else null;

        return ValueData(name, type, annotations, transient, static,
                \ivariable, setterAnnotations);
    }

    "Deserialize and return data identifying a Type Alias."
    shared TypeAliasData getTypeAliasData() {
        value name = getString();
        value annotations = getAnnotationData();
        value typeParameters = getTypeParametersData();
        assert(exists extendedType = getTypeData());
        value [satisfiedTypes, caseTypes] = getCaseAndSatisfiedTypes();

        return TypeAliasData(name, annotations, typeParameters, extendedType,
                caseTypes, satisfiedTypes);
    }

    "Deserialize and return data identifying a class."
    shared ClassData getClassData() {
        value name = getString();
        value annotations = getAnnotationData();

        value flags = get();
        value \iabstract = flags.and(classFlags.\iabstract) != 0.byte;
        value anonymous = flags.and(classFlags.anonymous) != 0.byte;
        value static = flags.and(classFlags.static) != 0.byte;
        value isAlias = flags.and(classFlags.\ialias) != 0.byte;
        value constructedAlias =
            flags.and(classFlags.constructedAlias) != 0.byte;

        value \ialias = if (constructedAlias)
            then getString()
            else isAlias;

        value typeParameters = getTypeParametersData();

        value parameters = getParameterListData();

        value extendedType = getTypeData();
        value [satisfiedTypes, caseTypes] = getCaseAndSatisfiedTypes();

        value members = ArrayList<DeclarationData>();

        while (exists d = getDeclarationData()) {
            members.add(d);
        }

        return ClassData(name, annotations, \ialias, \iabstract, anonymous,
                static, parameters, typeParameters, extendedType, caseTypes,
                satisfiedTypes, members);
    }

    "Deserialize and return data identifying an interface."
    shared InterfaceData getInterfaceData() {
        value name = getString();

        value annotations = getAnnotationData();

        value \ialias = get() != 0.byte;

        value typeParameters = getTypeParametersData();

        value extendedType = getTypeData();
        value [satisfiedTypes, caseTypes] = getCaseAndSatisfiedTypes();

        value members = ArrayList<DeclarationData>();

        while (exists d = getDeclarationData()) {
            members.add(d);
        }

        return InterfaceData(name, annotations, \ialias, typeParameters,
                extendedType, caseTypes, satisfiedTypes, members);
    }

    "Get a string, return null if we would return an empty string."
    String? getNonemptyString()
        => let (s = getString())
           if (!s.empty)
           then s
           else null;

    "Deserialize and return data identifying a constructor."
    shared ConstructorData getConstructorData()
        => ConstructorData(getNonemptyString(), getAnnotationData(),
                getParameterListData());

    "Load a declaration from the blob."
    shared DeclarationData? getDeclarationData() {
        value blobKey = get();

        if (blobKey == 0.byte) {
            return null;
        } else if (blobKey == blobKeys.\ifunction) {
            return getFunctionData();
        } else if (blobKey == blobKeys.\ival) {
            return getValueData();
        } else if (blobKey == blobKeys.\iinterface) {
            return getInterfaceData();
        } else if (blobKey == blobKeys.\iclass) {
            return getClassData();
        } else if (blobKey == blobKeys.\ialias) {
            return getTypeAliasData();
        } else if (blobKey == blobKeys.constructor) {
            return getConstructorData();
        } else {
            "Key byte should be a recognized value."
            assert(false);
        }
    }

    "Reset the read positiion."
    shared void rewind() {
        readPosition = 0;
    }

    "Size of this blob."
    shared Integer size => blob.size;
}
