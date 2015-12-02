import ceylon.io.base64 { encodeUrl }
import ceylon.io.charset { utf8 }

import com.redhat.ceylon.model.typechecker.model {
    Declaration,
    Scope,
    Package,
    TypeDeclaration,
    FunctionOrValue
}

import ceylon.interop.java {
    CeylonList
}

"Get the name prefix for items in a given package"
String declarationName(Declaration|Scope p) {
    if (is TypeDeclaration p) {
        return declarationName(p.container) + ".$``p.name``";
    }

    if (is FunctionOrValue p) {
        return declarationName(p.container) + ".``p.name``";
    }

    assert(is Package p);

    value v = p.\imodule.version;
    value pkg = CeylonList(p.name)
        .reduce<String>((x, y) => x.string + ".``y.string``")?.string;
    assert(exists pkg);

    return "c" + utf8.decode(encodeUrl(utf8.encode(v)))
            .replace("=", "")
            .replace("-", "$") + ".``pkg``";
}
