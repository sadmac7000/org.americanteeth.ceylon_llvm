import org.eclipse.ceylon.model.typechecker.model {
    TypeAlias,
    Unit,
    Scope
}

class TypeAliasData(name, annotations, typeParameters, extendedType,
        caseTypes, satisfiedTypes) extends DeclarationData() {
    shared String name;
    shared AnnotationData annotations;
    shared [TypeParameterData*] typeParameters;
    shared TypeData extendedType;
    shared {TypeData*} caseTypes;
    shared {TypeData*} satisfiedTypes;

    value ta = TypeAlias();
    shared actual TypeAlias declaration = ta;

    ta.name = name;
    annotations.apply(ta);
    applyTypeParameters(ta, typeParameters);

    shared actual void complete(Module mod, Unit unit, Scope container) {
        declaration.container = container;
        declaration.unit = unit;
        declaration.extendedType = extendedType.toType(mod, unit, declaration);

        setCaseAndSatisfiedTypes(mod, unit, declaration, caseTypes,
                satisfiedTypes);

        for (t in typeParameters) {
            t.complete(mod, unit, declaration);
        }
    }
}
