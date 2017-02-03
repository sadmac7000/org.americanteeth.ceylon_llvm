import com.redhat.ceylon.model.typechecker.model {
    Class,
    ClassAlias,
    ClassOrInterface,
    Function,
    Interface,
    InterfaceAlias,
    Scope,
    TypeDeclaration,
    Unit
}

abstract class ClassOrInterfaceData(name, annotations, \ialias, typeParameters,
        extendedType, caseTypes, satisfiedTypes, members)
        of ClassData|InterfaceData
        extends DeclarationData() {
    shared String name;
    shared AnnotationData annotations;
    shared Boolean \ialias;
    shared [TypeParameterData*] typeParameters;
    shared TypeData? extendedType;
    shared {TypeData*} caseTypes;
    shared {TypeData*} satisfiedTypes;
    shared {DeclarationData*} members;

    shared actual formal ClassOrInterface declaration;

    shared default void completeClass(Module mod, Unit unit) {}

    shared actual void complete(Module mod, Unit unit, Scope container) {
        declaration.container = container;
        declaration.unit = unit;
        declaration.extendedType = extendedType?.toType(mod, unit, declaration);
        setCaseAndSatisfiedTypes(mod, unit, declaration, caseTypes, satisfiedTypes);

        completeClass(mod, unit);

        for (t in typeParameters) {
            t.complete(mod, unit, declaration);
        }

        for (m in members) {
            m.complete(mod, unit, declaration);
        }
    }
}

class ClassData(n, a, als, \iabstract, anonymous, static, parameters, tp, et,
        ct, st, m)
        extends ClassOrInterfaceData(n, a, als != false, tp, et, ct, st, m) {
    String n;
    AnnotationData a;
    String|Boolean als;
    shared Boolean \iabstract;
    shared Boolean anonymous;
    shared Boolean static;
    shared ParameterListData? parameters;
    [TypeParameterData*] tp;
    TypeData? et;
    {TypeData*} ct;
    {TypeData*} st;
    {DeclarationData*} m;

    shared String? aliasName = if (is String als) then als else null;

    Class cls = if (als == false)
        then Class()
        else ClassAlias();

    cls.name = n;
    cls.\iabstract = \iabstract;
    cls.anonymous = anonymous;
    cls.static = static;
    applyTypeParameters(cls, tp);
    a.apply(cls);

    for (d in m) {
        cls.addMember(d.declaration);

        if (is ConstructorData d) {
            cls.addMember(d.functionOrValue);

            if (d.functionOrValue is Function) {
                cls.setConstructors(true);
            } else {
                cls.setEnumerated(true);
            }
        }
    }

    shared actual Class declaration = cls;

    shared actual void completeClass(Module mod, Unit unit) {
        cls.parameterList = parameters?.toParameterList(mod, unit, cls);

        if (exists c = cls.parameterList) {
            c.namedParametersSupported = true;
        }

        if (is ClassAlias cls) {
            if (is String als) {
                assert(is TypeDeclaration constructor =
                    cls.extendedType.declaration.getDirectMember(als, null,
                            false));
                cls.constructor = constructor;
            } else {
                cls.constructor = cls.extendedType.declaration;
            }
        }
    }
}

class InterfaceData(n, a, als, tp, et, ct, st, m)
        extends ClassOrInterfaceData(n, a, als, tp, et, ct, st, m) {
    String n;
    AnnotationData a;
    Boolean als;
    [TypeParameterData*] tp;
    TypeData? et;
    {TypeData*} ct;
    {TypeData*} st;
    {DeclarationData*} m;

    value int = if (als)
        then InterfaceAlias()
        else Interface();

    int.name = n;
    applyTypeParameters(int, tp);
    a.apply(int);

    for (d in m) {
        int.addMember(d.declaration);
    }

    shared actual Interface declaration = int;
}
