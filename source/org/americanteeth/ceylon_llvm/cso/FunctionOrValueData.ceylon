import org.eclipse.ceylon.model.typechecker.model {
    Declaration,
    FunctionOrValue,
    Function,
    Value,
    Scope,
    Setter,
    Unit
}

abstract class FunctionOrValueData(name, type, annotations)
        of FunctionData|ValueData
        extends DeclarationData() {
    shared actual formal FunctionOrValue declaration;

    shared String name;
    shared TypeData|ClassData? type;
    shared AnnotationData annotations;

    shared actual default void complete(Module mod, Unit unit,
            Scope container) {
        value parentDeclaration =
            if (is Declaration container)
            then container
            else null;

        if (is ClassData type) {
            type.complete(mod, unit, container);
        } else {
            declaration.type = type?.toType(mod, unit, parentDeclaration);
        }
    }
}

void applyParametersToFunction(Module mod, Unit unit, Function func,
        [ParameterListData+] parameterLists) {
    variable value first = true;

    for (data in parameterLists) {
        value p = data.toParameterList(mod, unit, func);
        p.namedParametersSupported = first;
        func.addParameterList(p);
        first = false;
    }
}

class FunctionData(n, t, a, typeParameters, declaredVoid, deferred, parameterLists)
        extends FunctionOrValueData(n, t, a) {
    String n;
    TypeData? t;
    AnnotationData a;
    [TypeParameterData*] typeParameters;
    shared Boolean declaredVoid;
    shared Boolean deferred;
    shared [ParameterListData+] parameterLists;

    value func = Function();

    func.name = n;
    func.declaredVoid = declaredVoid;
    func.deferred = deferred;
    a.apply(func);

    applyTypeParameters(func, typeParameters);

    shared actual Function declaration = func;

    shared actual void complete(Module mod, Unit unit, Scope container) {
        super.complete(mod, unit, container);
        applyParametersToFunction(mod, unit, func, parameterLists);

        for (t in typeParameters) {
            t.complete(mod, unit, func);
        }
    }
}

class ValueData(n, t, a, transient, static, \ivariable,
        setterAnnotations) extends FunctionOrValueData(n, t, a) {
    String n;
    TypeData|ClassData t;
    AnnotationData a;
    shared Boolean transient;
    shared Boolean static;
    shared Boolean \ivariable;
    shared AnnotationData? setterAnnotations;

    shared Boolean hasSetter = setterAnnotations exists;

    value val = Value();
    val.name = n;
    val.transient = transient;
    val.static = static;
    val.\ivariable = \ivariable;

    if (is ClassData t) {
        val.type = t.declaration.type;
    }

    a.apply(val);

    if (exists setterAnnotations) {
        val.setter = Setter();
        setterAnnotations.apply(val.setter);
        val.setter.name = val.name;
        val.setter.getter = val;
    }

    shared actual Value declaration = val;

    shared actual void complete(Module mod, Unit unit, Scope container) {
        super.complete(mod, unit, container);

        if (exists setterAnnotations) {
            val.setter.type = val.type;
        }
    }
}
