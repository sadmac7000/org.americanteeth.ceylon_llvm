import com.redhat.ceylon.model.typechecker.model {
    Declaration,
    IntersectionType,
    Scope,
    Type,
    TypeDeclaration,
    TypeParameter,
    UnionType,
    Unit,
    UnknownType,
    Value
}

import org.americanteeth.ceylon_llvm {
    CSOModule,
    CSOPackage
}

shared abstract class TypeDeclarationData() {
    shared formal TypeDeclaration toTypeDeclaration(CSOModule mod,
            Unit unit, Declaration? container);
}

object unknownTypeDeclarationData extends TypeDeclarationData() {
    shared actual UnknownType toTypeDeclaration(CSOModule mod, Unit unit,
            Declaration? container)
        => UnknownType(unit);
}

class UnionTypeDeclarationData(cases) extends TypeDeclarationData() {
    shared [<TypeData>+] cases;

    shared actual UnionType toTypeDeclaration(CSOModule mod, Unit unit,
            Declaration? container) {
        value ret = UnionType(unit);

        for (item in cases) {
            ret.caseTypes.add(item.toType(mod, unit, container));
        }

        return ret;
    }
}

class IntersectionTypeDeclarationData(satisfied) extends TypeDeclarationData() {
    shared [<TypeData>+] satisfied;

    shared actual IntersectionType toTypeDeclaration(CSOModule mod, Unit unit,
            Declaration? container) {
        value ret = IntersectionType(unit);

        for (item in satisfied) {
            ret.satisfiedTypes.add(item.toType(mod, unit, container));
        }

        return ret;
    }
}

class TypeParameterDeclarationData(name) extends TypeDeclarationData() {
    shared String name;

    shared actual TypeParameter toTypeDeclaration(CSOModule mod, Unit unit,
            Declaration? container) {
        "Type parameters aren't supported yet."
        assert(false);
    }
}

class PlainTypeDeclarationData(pkg, name) extends TypeDeclarationData() {
    shared [String+] pkg;
    shared [String+] name;

    shared actual TypeDeclaration toTypeDeclaration(CSOModule mod, Unit unit,
            Declaration? container) {
        "Type should be in an imported package."
        assert(is CSOPackage pkg = mod.getPackage(".".join(this.pkg)));

        if (name.size == 1) {
            "Referenced type should be defined."
            assert(is TypeDeclaration|Value t =
                    pkg.getDirectMember(name.first, null, false));

            return if (is Value t)
                then t.typeDeclaration
                else t;
        }

        variable Scope current = pkg;
        
        for (term in name) {
            value m = current.getMember(term, null, false);

            "Name should reference a type."
            assert(is Scope m);
            current = m;
        }

        "Member should be a type."
        assert(is TypeDeclaration ret = current);
        return ret;
    }
}

shared class TypeData(shared TypeDeclarationData declaration) {
    shared Type toType(CSOModule mod, Unit unit, Declaration? container)
        => declaration.toTypeDeclaration(mod, unit, container).type;
}
