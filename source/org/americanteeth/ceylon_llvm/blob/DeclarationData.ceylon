import com.redhat.ceylon.model.typechecker.model {
    Declaration,
    Scope,
    Unit
}

import org.americanteeth.ceylon_llvm {
    CSOModule
}

shared abstract class DeclarationData() {
    shared formal Declaration declaration;

    shared formal void complete(CSOModule mod, Unit unit, Scope container);
}
