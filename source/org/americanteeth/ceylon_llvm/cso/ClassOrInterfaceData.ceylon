import com.redhat.ceylon.model.typechecker.model {
    Class,
    ClassAlias,
    ClassOrInterface,
    Scope,
    TypeDeclaration,
    Unit
}

abstract class ClassOrInterfaceData()
        extends DeclarationData() {
    shared actual formal ClassOrInterface declaration;
}

class ClassData(name, annotations, \ialias, \iabstract, anonymous,
        static, typeParameters, parameters,
        extendedType, caseTypes, satisfiedTypes, members)
        extends ClassOrInterfaceData() {
    shared String name;
    shared AnnotationData annotations;
    shared String|Boolean \ialias;
    shared Boolean \iabstract;
    shared Boolean anonymous;
    shared Boolean static;
    shared [TypeParameterData*] typeParameters;
    shared ParameterListData? parameters;
    shared {DeclarationData*} members;
    shared TypeData? extendedType;
    shared {TypeData*} caseTypes;
    shared {TypeData*} satisfiedTypes;

    Class cls = if (\ialias == false)
        then Class()
        else ClassAlias();

    cls.name = name;
    cls.\iabstract = \iabstract;
    cls.anonymous = anonymous;
    cls.static = static;
    applyTypeParameters(cls, typeParameters);

    for (d in members) {
        cls.addMember(d.declaration);
    }

    shared actual Class declaration = cls;

    shared actual void complete(Module mod, Unit unit, Scope container) {
        cls.container = container;
        cls.unit = unit;
        annotations.apply(cls);
        cls.extendedType = extendedType?.toType(mod, unit, cls);

        for (type in caseTypes) {
            cls.caseTypes.add(type.toType(mod, unit, cls));
        }

        for (type in satisfiedTypes) {
            cls.satisfiedTypes.add(type.toType(mod, unit, cls));
        }

        cls.parameterList = parameters?.toParameterList(mod, unit,
                cls);
        cls.parameterList.namedParametersSupported = true;

        if (is ClassAlias cls) {
            if (is String \ialias) {
                assert(is TypeDeclaration constructor =
                    cls.extendedType.declaration.getDirectMember(\ialias, null,
                            false));
                cls.constructor = constructor;
            } else {
                cls.constructor = cls.extendedType.declaration;
            }
        }

        for (t in typeParameters) {
            t.complete(mod, unit, cls);
        }

        for (m in members) {
            m.complete(mod, unit, cls);
        }
    }
}
