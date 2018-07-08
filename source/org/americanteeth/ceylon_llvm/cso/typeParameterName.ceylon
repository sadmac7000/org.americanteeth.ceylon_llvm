import org.eclipse.ceylon.model.typechecker.model {
    Declaration,
    TypeParameter
}

"Get a partially qualified type parameter name."
String typeParameterName(TypeParameter t) {
    assert(is Declaration d = t.container);

    return "``partiallyQualifiedName(d)``.``t.name``";
}
