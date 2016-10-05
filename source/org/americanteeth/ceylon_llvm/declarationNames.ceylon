import ceylon.buffer.base {
    base64StringUrl
}
import ceylon.buffer.charset {
    utf8
}

import com.redhat.ceylon.model.typechecker.model {
    DeclarationModel=Declaration,
    ClassOrInterfaceModel=ClassOrInterface,
    ClassModel=Class,
    InterfaceModel=Interface,
    Scope,
    Package,
    TypeDeclaration,
    FunctionOrValue
}

import ceylon.interop.java {
    CeylonList
}

"Get the encoded name for a Ceylon Declaration.

 The encoding is a fully qualified name, preceded by a version marker.
 UIdentifiers are prefixed with $, all other terms are assumed to be
 LIdentifiers where applicable.

 The version marker is the character 'c' followed by the module version encoded
 in Base64, followed by a dot.

 The dialect of Base64 used is URL encoding, with no pad character, and '$'
 used instead of '-'.

 As an example, the 'String' class in version 1.3.0 of the ceylon.language
 package would be:

     cMS4zLjA.ceylon.language.$String
"
String declarationName(DeclarationModel|Scope p) {
    if (is TypeDeclaration p) {
        return declarationName(p.container) + ".$``p.name``";
    }

    if (is FunctionOrValue p) {
        return declarationName(p.container) + ".``p.name``";
    }

    if (! is Package p) {
        return declarationName(p.container);
    }

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

String vtableName(ClassModel|TypeDeclaration dec)
    => "``declarationName(dec)``$vtable";

String vtPositionName(DeclarationModel dec)
    => "``declarationName(dec)``$vtPosition";

String vtSizeName(ClassOrInterfaceModel|TypeDeclaration dec)
    => "``declarationName(dec)``$vtSize";

String sizeName(ClassModel|TypeDeclaration dec)
    => "``declarationName(dec)``$size";

String getterName(DeclarationModel dec)
    => "``declarationName(dec)``$get";

String setterName(DeclarationModel dec)
    => "``declarationName(dec)``$set";

String setupName(ClassOrInterfaceModel dec)
    => "``declarationName(dec)``$setup";

String initializerName(DeclarationModel dec)
    => "``declarationName(dec)``$init";

"Gives a name for a function declaration, marked as to whether it will do
 vtable dispatch."
String dispatchName(DeclarationModel model)
    => declarationName(model) + (if (model.\idefault) then "$noDispatch" else "");

String getterDispatchName(DeclarationModel model)
    => getterName(model) + (if (model.\idefault) then "$noDispatch" else "");

String setterDispatchName(DeclarationModel model)
    => setterName(model) + (if (model.\idefault) then "$noDispatch" else "");

String resolverName(ClassModel|TypeDeclaration dec)
    => "``declarationName(dec)``$resolveInterface";

String positionName(ClassModel model, InterfaceModel iface)
    => "``declarationName(model)``$position.``declarationName(iface)``";

String contextName = ".context";
String frameName = ".frame";

Ptr<I64Type> contextRegister = loc(ptr(i64), contextName);
Ptr<I64Type> frameRegister = loc(ptr(i64), frameName);

String memberName(ClassOrInterfaceModel model, String method)
    => "``declarationName(model)``.``method``";
