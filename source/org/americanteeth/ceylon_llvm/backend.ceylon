import org.eclipse.ceylon.common { Backend, Backends }
import org.eclipse.ceylon.model.typechecker.model {
    DeclarationModel=Declaration
}

shared Backend baremetalBackend = Backend.registerBackend("Bare Metal", "baremetal");

shared Boolean baremetalSupports(DeclarationModel model) {
    if (model.nativeBackends == Backends.\iANY ||
        model.nativeBackends == Backends.\iHEADER) {
        return true;
    }

    return model.nativeBackends.supports(baremetalBackend);
}
