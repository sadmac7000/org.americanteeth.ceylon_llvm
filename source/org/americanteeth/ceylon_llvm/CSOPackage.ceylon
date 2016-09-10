import com.redhat.ceylon.model.typechecker.model {
    Package,
    Scope,
    Module,
    Declaration,
    Function,
    FunctionOrValue,
    Type,
    TypeDeclaration,
    UnionType,
    IntersectionType,
    ParameterList,
    Parameter,
    Value,
    UnknownType,
    Unit
}

import ceylon.interop.java {
    CeylonList
}

import ceylon.collection {
    ArrayList
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

"Byte marking the start of a parameter list."
Byte startOfParameters = #ff.byte;

class CSOPackage() extends LazyPackage() {
    "Blob of binary data extracted from the module."
    variable CSOBlob? blobData = null;

    "A compilation unit for things that don't have one."
    value defaultUnit = Unit();
    variable value tmp = false;

    "Declaration for unknown types."
    value unknownDecl = UnknownType(defaultUnit);

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

        assert(!tmp);
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

        variable value b = data.get();
        while (b != 0.byte) {
            loadDeclaration(data, b);
            b = data.get();
        }
    }

    "Load a declaration from the blob."
    void loadDeclaration(CSOBlob data, Byte blobKey) {
        if (blobKey == blobKeys.method) {
            loadFunction(data, this);
        }

        /* TODO: Other declaration types */
    }

    "Consume and deserialize a function declaration."
    shared Function loadFunction(CSOBlob data, Scope parent) {
        value f = Function();
        f.name = data.getString();
        f.container = parent;
        f.unit = defaultUnit;

        if (parent == this) {
            defaultUnit.addDeclaration(f);
            addMember(null);
        }

        loadAnnotations(data, f);

        value flags = data.get();

        if (flags.and(functionFlags.\ivoid) != 0.byte) {
            f.declaredVoid = true;
        }

        if (flags.and(functionFlags.deferred) != 0.byte) {
            f.deferred = true;
        }

        /* TODO: Type parameters. */

        value parentDeclaration =
            if (is Declaration parent)
            then parent
            else null;

        f.type = loadType(data, parentDeclaration);

        variable value first = true;

        while (exists p = loadParameterList(data, f)) {
            p.namedParametersSupported = first;
            f.addParameterList(p);
            first = false;
        }

        "Function should have at least one parameter list."
        assert(!first);

        return f;
    }

    "Load a parameter list from the blob."
    ParameterList? loadParameterList(CSOBlob data, Declaration owner) {
        value ret = ParameterList();

        if (data.get() != startOfParameters) {
            return null;
        }

        while (exists param = loadParameter(data, owner)) {
            ret.parameters.add(param);
        }

        return ret;
    }

    "Load a parameter from the blob."
    Parameter? loadParameter(CSOBlob data, Declaration owner) {
        value name = data.getString();

        if (name.empty) {
            return null;
        }

        value param = Parameter();
        value flags = data.get();

        param.name = name;
        param.declaration = owner;
        param.hidden = flags.and(parameterFlags.hidden) != 0.byte;
        param.defaulted = flags.and(parameterFlags.defaulted) != 0.byte;
        param.sequenced = flags.and(parameterFlags.sequenced) != 0.byte;
        param.atLeastOne = flags.and(parameterFlags.atLeastOne) != 0.byte;

        if (flags.and(parameterFlags.functionParameter) != 0.byte) {
            value f = Function();
            param.model = f;

            variable value first = true;

            while (exists p = loadParameterList(data, f)) {
                p.namedParametersSupported = first;
                f.addParameterList(p);
                first = false;
            }

            "Function argument should have at least one parameter list."
            assert(!first);
        } else {
            param.model = Value();
        }

        assert(exists m = param.model);
        m.initializerParameter = param;
        m.name = name;
        m.unit = defaultUnit;

        if (is Scope owner) {
            m.container = owner;
        }

        "Parameter should have a type."
        assert(exists type = loadType(data, owner));
        m.type = type;

        loadAnnotations(data, m);

        return param;
    }

    "Load a type declaration from the blob."
    TypeDeclaration? loadTypeDeclaration(CSOBlob data, Declaration? container) {
        value typeKind = data.get();

        if (typeKind == 0.byte) {
            return null;
        }

        if (typeKind == typeKinds.unknown) {
            return unknownDecl;
        }

        if (typeKind == typeKinds.union) {
            value ret = UnionType(defaultUnit);

            while (exists t = loadType(data, container)) {
                ret.caseTypes.add(t);
            }

            return ret;
        }

        if (typeKind == typeKinds.intersection) {
            value ret = IntersectionType(defaultUnit);

            while (exists t = loadType(data, container)) {
                ret.satisfiedTypes.add(t);
            }

            return ret;
        }

        /* TODO */
        "Type parameters aren't yet supported."
        assert(typeKind != typeKinds.parameter);

        "Should have found a valid type kind indicatior."
        assert(typeKind == typeKinds.plain);

        value packageName = ".".join(data.getStringList());

        "Package should be found."
        assert(exists pkg = \imodule?.getPackage(packageName));

        if (is CSOPackage pkg) { pkg.load(); }

        value name = data.getStringList();

        "Package name should have at least one term."
        assert(exists level1 = name.first);

        if (name.size == 1) {
            "Package should have member matching type declaration."
            assert(exists d = pkg.getDirectMember(level1, null, false));

            if (is TypeDeclaration d) {
                return d;
            }

            if (is FunctionOrValue d) {
                return d.typeDeclaration;
            }
        }

        if (is CSOPackage pkg) {
            "TODO: loadNestedType equivalent to dart back end."
            assert(false);
        }

        "Only nested types should remain."
        assert(name.size > 1);

        variable Declaration? result = null;

        for (d in pkg.members) {
            if (is TypeDeclaration d, d.name == level1) {
                return d;
            }
        }

        for (term in name.rest) {
            "Should have a base declaration."
            assert(is TypeDeclaration r = result);

            "Should have appropriate member."
            assert(exists m = r.getDirectMember(term, null, false));
            result = m;
        }

        "Should produce a final result."
        assert(is TypeDeclaration r = result);
        return r;
    }

    "Load a Type object from the blob."
    Type? loadType(CSOBlob data, Declaration? parent) {
        value typeDeclaration = loadTypeDeclaration(data, parent);

        if (! exists typeDeclaration) {
            return null;
        }

        if (is UnknownType typeDeclaration) {
            return typeDeclaration.type;
        }

        /* TODO: Type parameters. */
        return typeDeclaration.type;
    }

    "Write one member to the blob."
    void storeMember(CSOBlob buf, Declaration d) {
        if (is Function d) {
            buf.put(blobKeys.method);
            storeFunction(buf, d);
        }

        /* TODO: Other declaration types */
    }

    "Write one function member to the blob."
    void storeFunction(CSOBlob buf, Function f) {
        buf.putString(f.name);

        storeAnnotations(buf, f);

        variable value flags = 0.byte;

        if (f.declaredVoid) {
            flags = flags.or(functionFlags.\ivoid);
        }

        if (f.deferred) {
            flags = flags.or(functionFlags.deferred);
        }

        buf.put(flags);

        /* TODO: Type parameters. */

        storeType(buf, f.type);

        for (p in f.parameterLists) {
            storeParameterList(buf, p);
        }

        buf.put(0.byte);
    }

    "Write one type to the blob."
    void storeType(CSOBlob buf, Type t) {
        storeTypeDeclaration(buf, t.declaration);
        /* TODO: Type parameters. */
    }

    "Write a parameter list to the blob."
    void storeParameterList(CSOBlob buf, ParameterList p) {
        buf.put(startOfParameters);

        for (param in p.parameters) {
            storeParameter(buf, param);
        }

        buf.put(0.byte);
    }

    "Write a parameter to the blob."
    void storeParameter(CSOBlob buf, Parameter param) {
        buf.putString(param.name);

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
            buf.put(flags);

            for (plist in model.parameterLists) {
                storeParameterList(buf, plist);
            }

            buf.put(0.byte);
        } else {
            buf.put(flags);
        }

        storeType(buf, model.type);

        storeAnnotations(buf, model);
    }

    "Store a type declaration to the blob."
    void storeTypeDeclaration(CSOBlob buf, TypeDeclaration t) {
        if (is UnknownType t) {
            buf.put(typeKinds.unknown);
            return;
        }

        if (is UnionType t) {
            buf.put(typeKinds.union);

            for (sub in t.caseTypes) {
                storeType(buf, sub);
            }

            buf.put(0.byte);
            return;
        }

        if (is IntersectionType t) {
            buf.put(typeKinds.intersection);

            for (sub in t.satisfiedTypes) {
                storeType(buf, sub);
            }

            buf.put(0.byte);
            return;
        }

        buf.put(typeKinds.plain);

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

        buf.putStringList(p.name);
        name.add(t.name);
        buf.putStringList(name);
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
