import ceylon.buffer.base {
    base64StringUrl
}
import ceylon.buffer.charset {
    utf8
}

import org.eclipse.ceylon.model.typechecker.model {
    DeclarationModel=Declaration,
    ClassOrInterfaceModel=ClassOrInterface,
    ClassModel=Class,
    ConstructorModel=Constructor,
    InterfaceModel=Interface,
    Scope,
    TypeDeclaration,
    Setter,
    FunctionOrValue
}

import ceylon.interop.java {
    CeylonList
}

String fullName(TypeDeclaration|FunctionOrValue p) {
    value name = if (is FunctionOrValue p)
        then p.name
        else if (p.name.startsWith("anonymous#"))
        then p.name.replace("#", "$")
        else "$``p.name``";

    if (exists q = p.qualifier) {
        return "``name``$q``q``";
    } else {
        return name;
    }
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
    assert(exists scope = nearestAllocatingScope(p));

    if (is ConstructorModel p, ! p.name exists) {
        return declarationName(scope.container) + ".$$";
    }

    if (is TypeDeclaration|FunctionOrValue scope) {
        return declarationName(scope.container) + ".``fullName(scope)``" +
            (if (is Setter scope) then "$set" else "");
    }

    String? v = scope.\imodule.version;
    value pkg = CeylonList(scope.name)
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
    => if (is Setter dec) then declarationName(dec)
       else "``declarationName(dec)``$set";

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
String valueName = ".value";

String memberName(ClassOrInterfaceModel model, String method)
    => "``declarationName(model)``.``method``";
