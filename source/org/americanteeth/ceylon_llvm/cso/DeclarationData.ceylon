import com.redhat.ceylon.model.typechecker.model {
    Declaration,
    Scope,
    Unit
}

abstract class DeclarationData() {
    shared formal Declaration declaration;

    shared formal void complete(Module mod, Unit unit, Scope container);
}
