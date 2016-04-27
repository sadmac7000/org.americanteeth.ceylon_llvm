import ceylon.buffer.base {
    base64StringUrl
}
import ceylon.buffer.charset {
    utf8
}

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

    assert (is Package p);

    String? v = p.\imodule.version;
    value pkg = CeylonList(p.name)
        .reduce<String>((x, y) => x.string + ".``y.string``")?.string;
    assert (exists pkg);

    value vEncoded =
        if (exists v)
        then base64StringUrl.encode(utf8.encode(v))
                .replace("=", "")
                .replace("-", "$")
        else "";

    return "c``vEncoded``.``pkg``";
}
