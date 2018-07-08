import org.eclipse.ceylon.model.typechecker.model {
    Class,
    Constructor,
    Function,
    FunctionOrValue,
    Scope,
    Type,
    Unit,
    Value
}

import ceylon.interop.java {
    JavaList
}

class ConstructorData(name, annotations, parameterList) extends DeclarationData() {
    shared String? name;
    shared AnnotationData annotations;
    shared ParameterListData? parameterList;

    value constructor = Constructor();
    constructor.name = name;
    constructor.\idynamic = false;
    annotations.apply(constructor);

    shared FunctionOrValue functionOrValue = if (exists parameterList)
        then Function() else Value();

    functionOrValue.name = name;

    shared actual Constructor declaration = constructor;

    shared actual void complete(Module mod, Unit unit, Scope container) {
        "Constructor should always be in a class."
        assert(is Class container);

        constructor.container = container;
        constructor.scope = container;
        constructor.unit = unit;
        constructor.extendedType = container.type;

        if (is Function functionOrValue) {
            "Functional constructor should have a parameter list."
            assert(exists parameterList);

            value plist = parameterList.toParameterList(mod, unit,
                    container);

            constructor.addParameterList(plist);
            plist.namedParametersSupported = true;

            functionOrValue.type =
                constructor.appliedType(constructor.extendedType,
                        JavaList<Type>([]));
        } else {
            functionOrValue.type = constructor.type;
        }

        functionOrValue.container = container;
        functionOrValue.scope = container;
        functionOrValue.unit = unit;
        functionOrValue.visibleScope = constructor.visibleScope;
        functionOrValue.\ishared = constructor.\ishared;
        functionOrValue.deprecated = constructor.deprecated;
    }
}
