import com.redhat.ceylon.common {
    Backends
}

import com.redhat.ceylon.model.typechecker.model {
    Package,
    Scope,
    Module,
    Cancellable,
    Declaration,
    DeclarationWithProximity,
    Type,
    TypeDeclaration,
    Import,
    Unit
}

import java.lang {
    JIterable=Iterable,
    JString=String
}

import java.util {
    JList=List,
    JMap=Map
}

shared abstract class LazyPackage() extends Package() {
    "Load this package's data."
    shared formal void load();

    shared actual Boolean toplevel {
        load();
        return super.toplevel;
    }

    shared actual default Module? \imodule {
        load();
        return super.\imodule;
    }
    assign \imodule {
        super.\imodule = \imodule;
    }

    shared actual JIterable<Unit> units {
        load();
        return super.units;
    }

    shared actual Boolean \ishared {
        load();
        return super.\ishared;
    }
    assign \ishared {
        super.\ishared = \ishared;
    }

    shared actual JList<Declaration>? members {
        load();
        return super.members;
    }

    shared actual Scope? container {
        load();
        return super.container;
    }

    shared actual Scope? scope {
        load();
        return super.scope;
    }

    shared actual Unit unit {
        load();
        return super.unit;
    }
    assign unit {
        super.unit = unit;
    }

    shared actual Backends scopedBackends {
        load();
        return super.scopedBackends;
    }

    shared actual String string {
        load();
        return super.string;
    }

    shared actual Integer hash {
        load();
        return super.hash;
    }

    shared actual Declaration? getMember(String name, JList<Type>? signature,
            Boolean variadic) {
        load();
        return super.getMember(name, signature, variadic);
    }

    shared actual Declaration? getDirectMember(String name,
            JList<Type>? signature, Boolean variadic) {
        load();
        return super.getDirectMember(name, signature, variadic);
    }

    shared actual Declaration? getDirectMemberForBackend(String name,
            Backends backends) {
        load();
        return super.getDirectMemberForBackend(name, backends);
    }

    shared actual Type? getDeclaringType(Declaration d) {
        load();
        return super.getDeclaringType(d);
    }

    shared actual Declaration? getMemberOrParameter(Unit unit, String name,
            JList<Type> signature, Boolean variadic) {
        load();
        return super.getMemberOrParameter(unit, name, signature, variadic);
    }

    shared actual Boolean isInherited(Declaration d) {
        load();
        return super.isInherited(d);
    }

    shared actual TypeDeclaration? getInheritingDeclaration(Declaration d) {
        load();
        return super.getInheritingDeclaration(d);
    }

    shared actual JMap<JString,DeclarationWithProximity>
        getMatchingDeclarations(Unit unit, String startingWith,
            Integer proximity, Cancellable? canceller) {
        load();
        return super.getMatchingDeclarations(unit, startingWith,
                proximity, canceller);
    }

    shared actual JMap<JString,DeclarationWithProximity>
        getMatchingDirectDeclarations(String startingWith,
            Integer proximity, Cancellable? canceller) {
        load();
        return super.getMatchingDirectDeclarations(startingWith, proximity, canceller);
    }

    shared actual JMap<JString,DeclarationWithProximity>
        getImportableDeclarations(Unit unit, String startingWith,
            JList<Import> imports, Integer proximity, Cancellable? canceller) {
        load();
        return super.getImportableDeclarations(unit, startingWith,
                imports, proximity, canceller);
    }

    shared actual Boolean equals(Object other) {
        load();
        return super.equals(other);
    }
}
