import com.redhat.ceylon.model.typechecker.model {
    Declaration,
    Generic
}

import ceylon.interop.java {
    JavaList
}

void applyTypeParameters(Declaration&Generic g, [TypeParameterData*] typeParameters) {
    value reifiedTypeParameters =
        typeParameters.collect((x) => x.typeParameter);

    for (p in reifiedTypeParameters) {
        g.members.add(p);
    }

    g.typeParameters = JavaList(reifiedTypeParameters);
}