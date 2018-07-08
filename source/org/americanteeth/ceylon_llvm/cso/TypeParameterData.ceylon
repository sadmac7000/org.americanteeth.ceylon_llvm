import org.eclipse.ceylon.model.typechecker.model {
    Declaration,
    Generic,
    Scope,
    TypeParameter,
    Unit
}

class TypeParameterData(name, variance, defaultType, extendedType,
        satisfiedTypes, caseTypes) {
    shared String name;
    shared Variance variance;
    shared TypeData? extendedType;
    shared TypeData? defaultType;
    shared {TypeData*} satisfiedTypes;
    shared {TypeData*} caseTypes;

    shared TypeParameter typeParameter = TypeParameter();

    typeParameter.name = name;
    typeParameter.covariant = variance == Variance.covariant;
    typeParameter.contravariant = variance == Variance.contravariant;
    typeParameter.defaulted = defaultType exists;

    shared void complete(Module mod, Unit unit, Declaration&Generic container) {
        typeParameter.unit = unit;
        typeParameter.declaration = container;

        if (is Scope container) {
            typeParameter.container = container;
        }

        typeParameter.extendedType = extendedType?.toType(mod, unit,
                container);
        typeParameter.defaultTypeArgument = defaultType?.toType(mod, unit,
                container);

        setCaseAndSatisfiedTypes(mod, unit, typeParameter, caseTypes,
                satisfiedTypes);
    }
}
