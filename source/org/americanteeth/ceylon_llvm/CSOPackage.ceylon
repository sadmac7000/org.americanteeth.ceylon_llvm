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
    Setter,
    Value,
    UnknownType,
    Unit
}

import ceylon.interop.java {
    CeylonList
}

import ceylon.collection {
    ArrayList,
    HashMap
}

import ceylon.promise {
    Deferred,
    Promise
}

import org.americanteeth.ceylon_llvm.blob {
    CSOBlob,
    blobKeys,
    loadAnnotations,
    storeAnnotations
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

"Byte marking the start of a parameter list."
Byte startOfParameters = #ff.byte;

class CSOPackage() extends LazyPackage() {
    "Blob of binary data extracted from the module."
    variable CSOBlob? blobData = null;

    "A compilation unit for things that don't have one."
    value defaultUnit = Unit();

    "Declaration for unknown types."
    value unknownDecl = UnknownType(defaultUnit);

    "Deferred accessor to unknownDecl"
    value unknownDeclDeferred = Deferred<UnknownType>();

    unknownDeclDeferred.fulfill(unknownDecl);

    "Promises of values to be delivered later."
    value deferreds = HashMap<String,Deferred<Declaration>>();

    "Get a promise if we aren't done loading."
    shared Promise<Declaration> expectDirectMember(String name) {
        if (exists e = deferreds[name]) {
            return e.promise;
        }

        value deferred = Deferred<Declaration>();

        if (exists d = getDirectMember(name, null, false)) {
            deferred.fulfill(d);
        }

        deferreds[name] = deferred;
        return deferred.promise;
    }

    "Add a direct member we just loaded."
    void addLoadedMember(Declaration member) {
        defaultUnit.addDeclaration(member);
        addMember(member);

        if (exists d = deferreds[member.name]) {
            d.fulfill(member);
        }
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

        if (blobKey == 0.byte) {
            return false;
        } else if (blobKey == blobKeys.\ifunction) {
            loadFunctionOrValue(Function(), data, parent);
        } else if (blobKey == blobKeys.\ival) {
            loadFunctionOrValue(Value(), data, parent);
        } else if (blobKey == blobKeys.\iinterface) {
            loadInterface(data, parent);
        } else if (blobKey == blobKeys.\iclass) {
            loadClass(data, parent);
        } else if (blobKey == blobKeys.\iobject) {
            loadObject(data, parent);
        } else if (blobKey == blobKeys.\ialias) {
            loadAlias(data, parent);
        } else {
            "Key byte should be a recognized value."
            assert(false);
        }

        return true;
    }

    void loadInterface(CSOBlob data, Scope parent) {}
    void loadClass(CSOBlob data, Scope parent) {}
    void loadObject(CSOBlob data, Scope parent) {}
    void loadAlias(CSOBlob data, Scope parent) {}

    "Consume and deserialize a function or value declaration."
    void loadFunctionOrValue(FunctionOrValue f, CSOBlob data, Scope parent) {
        f.name = data.getString();
        f.container = parent;
        f.unit = defaultUnit;

        if (parent == this) {
            addLoadedMember(f);
        }

        loadAnnotations(data, f);

        value parentDeclaration =
            if (is Declaration parent)
            then parent
            else null;

        value gottenType = loadType(data, parentDeclaration);

        if (exists gottenType) {
            gottenType.completed((x) => f.type = x);
        }

        value flags = data.get();

        if (is Function f) {
            if (flags.and(functionFlags.\ivoid) != 0.byte) {
                f.declaredVoid = true;
            }

            if (flags.and(functionFlags.deferred) != 0.byte) {
                f.deferred = true;
            }
        } else {
            assert(is Value f);
            if (flags.and(valueFlags.transient) != 0.byte) {
                f.transient = true;
            }

            if (flags.and(valueFlags.static) != 0.byte) {
                f.staticallyImportable = true;
            }

            if (flags.and(valueFlags.\ivariable) != 0.byte) {
                f.\ivariable = true;
            }

            if (flags.and(valueFlags.hasSetter) != 0.byte) {
                f.setter = Setter();
                f.setter.name = f.name;
                f.setter.container = parent;
                f.setter.unit = defaultUnit;
                f.setter.getter = f;

                if (exists gottenType) {
                    gottenType.completed((x) => f.setter.type = x);
                }

                if (parent == this) {
                    addLoadedMember(f.setter);
                }

                loadAnnotations(data, f.setter);
            }
        }

        /* TODO: Type parameters. */

        if (is Value f) {
            return;
        }

        assert(is Function f);

        variable value first = true;

        while (exists p = loadParameterList(data, f)) {
            p.namedParametersSupported = first;
            f.addParameterList(p);
            first = false;
        }

        "Function should have at least one parameter list."
        assert(!first);
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
        type.completed((x) => m.type = x);

        loadAnnotations(data, m);

        return param;
    }

    "Load a type declaration from the blob."
    Promise<TypeDeclaration>? loadTypeDeclaration(CSOBlob data,
            Declaration? container) {
        value typeKind = data.get();

        if (typeKind == 0.byte) {
            return null;
        }

        if (typeKind == typeKinds.unknown) {
            return unknownDeclDeferred.promise;
        }

        if (typeKind == typeKinds.union) {
            value ret = UnionType(defaultUnit);

            while (exists t = loadType(data, container)) {
                t.completed { (x) => ret.caseTypes.add(x); };
            }

            value def = Deferred<UnionType>();
            def.fulfill(ret);

            return def.promise;
        }

        if (typeKind == typeKinds.intersection) {
            value ret = IntersectionType(defaultUnit);

            while (exists t = loadType(data, container)) {
                t.completed { (x) => ret.satisfiedTypes.add(x); };
            }

            value def = Deferred<IntersectionType>();
            def.fulfill(ret);

            return def.promise;
        }

        /* TODO */
        "Type parameters aren't yet supported."
        assert(typeKind != typeKinds.parameter);

        "Should have found a valid type kind indicatior."
        assert(typeKind == typeKinds.plain);

        value packageName = ".".join(data.getStringList());

        "Package should be found, and from the baremetal backend."
        assert(is CSOPackage pkg = \imodule?.getPackage(packageName));

        if (pkg != this) { pkg.load(); }

        value name = data.getStringList();

        "Package name should have at least one term."
        assert(exists level1 = name.first);

        if (name.size == 1) {
            return expectDirectMember(level1).map {
                (x) {
                    "Fetched member should map to a type."
                    assert(is TypeDeclaration|FunctionOrValue x);

                    if (is TypeDeclaration x) {
                        return x;
                    } else {
                        return x.typeDeclaration;
                    }
                };
            };
        }

        return expectDirectMember(level1).map {
            (x) {
                variable value ret = x;

                for (item in name[1...]) {
                    "Type member should be present."
                    assert(exists r = ret.getMember(item, null, false));
                    ret = r;
                }

                assert(is TypeDeclaration r = ret);
                return r;
            };
        };
    }

    "Load a Type object from the blob."
    Promise<Type>? loadType(CSOBlob data, Declaration? parent) {
        value typeDeclaration = loadTypeDeclaration(data, parent);

        if (! exists typeDeclaration) {
            return null;
        }

        /* TODO: Type parameters. */

        return typeDeclaration.map((x) => x.type);
    }

    "Write one member to the blob."
    void storeMember(CSOBlob buf, Declaration d) {
        if (is Function d) {
            buf.put(blobKeys.\ifunction);
            storeFunctionOrValue(buf, d);
        } else if (is Value d) {
            buf.put(blobKeys.\ival);
            storeFunctionOrValue(buf, d);
        }

        /* TODO: Other declaration types */
    }

    "Write one function member to the blob."
    void storeFunctionOrValue(CSOBlob buf, FunctionOrValue f) {
        buf.putString(f.name);

        storeAnnotations(buf, f);

        storeType(buf, f.type);

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

        buf.put(flags);

        if (is Value f, exists s = f.setter) {
            storeAnnotations(buf, s);
        }

        /* TODO: Type parameters. */

        if (is Value f) {
            return;
        }

        assert(is Function f);

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
