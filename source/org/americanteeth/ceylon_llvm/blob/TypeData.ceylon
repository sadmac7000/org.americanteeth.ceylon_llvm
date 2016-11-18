import com.redhat.ceylon.model.typechecker.model {
    Declaration,
    Generic,
    IntersectionType,
    ModelUtil,
    Scope,
    SiteVariance,
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

import java.util {
    JHashMap = HashMap
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

shared class TypeData(shared TypeDeclarationData declaration,
        Map<String,TypeArgumentData>? arguments) {
    shared Type toType(CSOModule mod, Unit unit, Declaration? container) {
        value baseDecl = declaration.toTypeDeclaration(mod, unit, container);
        value base = baseDecl.type;

        if (! exists arguments) {
            return base;
        }

        variable Declaration? current = baseDecl;

        value concretes = JHashMap<TypeParameter,Type>();
        variable JHashMap<TypeParameter,SiteVariance>? variances_ = null;
        value variances
            => variances_
            else (variances_ = JHashMap<TypeParameter,SiteVariance>());

        while (exists d = current) {
            if (! is Generic d) {
                continue;
            }

            for (parameter in d.typeParameters) {
                "Container's parameters should be satisfied."
                assert(exists argument =
                    arguments["``partiallyQualifiedName(d)``.``parameter.name``"]);

                concretes.put(parameter, argument.type.toType(mod, unit,
                            container));

                if (exists v = argument.useSiteVariance.siteVariance) {
                    variances.put(parameter, v);
                }
            }

            current = ModelUtil.getContainingDeclaration(d);
        }

        return base.substitute(concretes, variances);
    }
}

shared class Variance {
    shared SiteVariance? siteVariance;

    shared new covariant {
        this.siteVariance = SiteVariance.\iOUT;
    }

    shared new contravariant {
        this.siteVariance = SiteVariance.\iIN;
    }

    shared new invariant {
        this.siteVariance = null;
    }
}

shared class TypeArgumentData(useSiteVariance, type) {
    shared Variance useSiteVariance;
    shared TypeData type;
}
