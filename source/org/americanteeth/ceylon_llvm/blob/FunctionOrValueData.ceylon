import com.redhat.ceylon.model.typechecker.model {
    Declaration,
    FunctionOrValue,
    Function,
    Value,
    ParameterList,
    Parameter,
    Scope,
    Setter,
    Unit
}

import org.americanteeth.ceylon_llvm {
    CSOModule
}

shared abstract class FunctionOrValueData(name, type, annotations)
        extends DeclarationData() {
    shared actual formal FunctionOrValue declaration;

    shared String name;
    shared TypeData? type;
    shared AnnotationData annotations;

    shared actual default void complete(CSOModule mod, Unit unit,
            Scope container) {
        value parentDeclaration =
            if (is Declaration container)
            then container
            else null;

        declaration.type = type?.toType(mod, unit, parentDeclaration);
    }
}

void applyParametersToFunction(CSOModule mod, Unit unit, Function func,
        [ParameterListData+] parameterLists) {
    variable value first = true;

    for (data in parameterLists) {
        value p = data.toParameterList(mod, unit, func);
        p.namedParametersSupported = first;
        func.addParameterList(p);
        first = false;
    }
}

shared class FunctionData(n, t, a, declaredVoid, deferred, parameterLists)
        extends FunctionOrValueData(n, t, a) {
    String n;
    TypeData? t;
    AnnotationData a;
    shared Boolean declaredVoid;
    shared Boolean deferred;
    shared [ParameterListData+] parameterLists;

    value func = Function();

    func.name = n;
    func.declaredVoid = declaredVoid;
    func.deferred = deferred;
    a.apply(func);

    shared actual Function declaration = func;

    shared actual void complete(CSOModule mod, Unit unit, Scope container) {
        super.complete(mod, unit, container);
        applyParametersToFunction(mod, unit, func, parameterLists);
    }
}

shared class ValueData(n, t, a, transient, staticallyImportable, \ivariable,
        setterAnnotations) extends FunctionOrValueData(n, t, a) {
    String n;
    TypeData t;
    AnnotationData a;
    shared Boolean transient;
    shared Boolean staticallyImportable;
    shared Boolean \ivariable;
    shared AnnotationData? setterAnnotations;

    shared Boolean hasSetter = setterAnnotations exists;

    value val = Value();
    val.name = n;
    val.transient = transient;
    val.staticallyImportable = staticallyImportable;
    val.\ivariable = \ivariable;
    a.apply(val);

    if (exists setterAnnotations) {
        val.setter = Setter();
        setterAnnotations.apply(val.setter);
        val.setter.name = val.name;
        val.setter.getter = val;
    }

    shared actual Value declaration = val;

    shared actual void complete(CSOModule mod, Unit unit, Scope container) {
        super.complete(mod, unit, container);

        if (exists setterAnnotations) {
            val.setter.type = val.type;
        }
    }
}

shared class ParameterListData([ParameterData*] parameters) {
    shared ParameterList toParameterList(CSOModule mod, Unit unit,
            Declaration container) {
        value ret = ParameterList();

        for (parameter in parameters) {
            ret.parameters.add(parameter.toParameter(mod, unit, container));
        }

        return ret;
    }
}

shared class ParameterType {
    shared new normal {}
    shared new zeroOrMore {}
    shared new oneOrMore {}
}

shared class ParameterData(name, hidden, defaulted, parameterType, parameters,
        type, annotations) {
    shared String name;
    shared Boolean hidden;
    shared Boolean defaulted;
    shared ParameterType parameterType;
    shared [ParameterListData*] parameters;
    shared TypeData type;
    shared AnnotationData annotations;

    shared Parameter toParameter(CSOModule mod, Unit unit, Declaration container) {
        value ret = Parameter();

        ret.name = name;
        ret.declaration = container;
        ret.hidden = hidden;
        ret.defaulted = defaulted;
        ret.sequenced = parameterType != ParameterType.normal;
        ret.atLeastOne = parameterType == ParameterType.oneOrMore;

        FunctionOrValue f;

        if (nonempty parameters) {
            f = Function();
            assert(is Function f);
            applyParametersToFunction(mod, unit, f, parameters);
        } else {
            f = Value();
        }

        ret.model = f;
        f.initializerParameter = ret;
        f.name = name;
        f.unit = unit;

        if (is Scope container) {
            f.container = container;
        }

        f.type = type.toType(mod, unit, f);
        annotations.apply(f);

        return ret;
    }
}
