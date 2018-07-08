import org.eclipse.ceylon.model.typechecker.model {
    TypeDeclaration,
    Unit
}

import ceylon.interop.java {
    JavaList
}

void setCaseAndSatisfiedTypes(Module mod, Unit unit,
        TypeDeclaration declaration, {TypeData*}? caseTypes,
        {TypeData*}? satisfiedTypes) {
    if (exists caseTypes) {
        declaration.caseTypes = JavaList(caseTypes.collect(
                        (x) => x.toType(mod, unit, declaration)));
    }

    if (exists satisfiedTypes) {
        declaration.satisfiedTypes = JavaList(satisfiedTypes.collect(
                        (x) => x.toType(mod, unit, declaration)));
    }
}
