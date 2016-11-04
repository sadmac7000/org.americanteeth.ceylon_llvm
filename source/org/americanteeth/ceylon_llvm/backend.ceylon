import com.redhat.ceylon.common { Backend, Backends }
import com.redhat.ceylon.model.typechecker.model {
    DeclarationModel=Declaration
}

shared Backend baremetalBackend = Backend.registerBackend("Bare Metal", "baremetal");

Boolean baremetalSupports(DeclarationModel model) {
    if (model.nativeBackends == Backends.\iANY) {
        return true;
    }

    return model.nativeBackends.supports(baremetalBackend);
}
