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

import java.util {
    JHashMap = HashMap
}

abstract class TypeDeclarationData() {
    shared formal TypeDeclaration toTypeDeclaration(Module mod,
            Unit unit, Declaration? container);
}

object unknownTypeDeclarationData extends TypeDeclarationData() {
    shared actual UnknownType toTypeDeclaration(Module mod, Unit unit,
            Declaration? container)
        => UnknownType(unit);
}

class UnionTypeDeclarationData(cases) extends TypeDeclarationData() {
    shared [<TypeData>+] cases;

    shared actual UnionType toTypeDeclaration(Module mod, Unit unit,
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

    shared actual IntersectionType toTypeDeclaration(Module mod, Unit unit,
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

    shared actual TypeParameter toTypeDeclaration(Module mod, Unit unit,
            Declaration? container) {
        variable Declaration? d = container;

        while (exists current = d) {
            if (is Generic current) {
                for (t in current.typeParameters) {
                    if (t.name == name) {
                        return t;
                    }
                }
            }

            d = ModelUtil.getContainingDeclaration(current);
        }

        "Type parameters should be declared in a container."
        assert(false);
    }
}

class PlainTypeDeclarationData(pkg, name) extends TypeDeclarationData() {
    shared [String+] pkg;
    shared [String+] name;

    shared actual TypeDeclaration toTypeDeclaration(Module mod, Unit unit,
            Declaration? container) {
        "Type should be in an imported package."
        assert(is Package pkg = mod.getPackage(".".join(this.pkg)));

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

class TypeData(shared TypeDeclarationData declaration,
        Map<String,TypeArgumentData>? arguments) {
    shared Type toType(Module mod, Unit unit, Declaration? container) {
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

class TypeArgumentData(useSiteVariance, type) {
    shared Variance useSiteVariance;
    shared TypeData type;
}
