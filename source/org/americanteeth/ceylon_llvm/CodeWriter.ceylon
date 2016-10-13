import com.redhat.ceylon.model.typechecker.model {
    DeclarationModel=Declaration,
    TypeDeclaration,
    FunctionModel=Function,
    ValueModel=Value,
    ClassModel=Class,
    InterfaceModel=Interface,
    SetterModel=Setter,
    PackageModel=Package,
    TypeModel=Type
}

import ceylon.ast.core {
    Node
}

interface CodeWriter {
    shared formal Scope scope;
    shared formal T push<T>(T m) given T satisfies Scope;
    shared formal void pop(Scope check);
    shared formal ExpressionTransformer expressionTransformer;
    shared formal PackageModel languagePackage;

    shared GetterScope getterScope(ValueModel model)
        => push(GetterScope(model, pop));
    shared SetterScope setterScope(SetterModel model)
        => push(SetterScope(model, pop));
    shared ConstructorScope constructorScope(ClassModel model)
        => push(ConstructorScope(model, pop));
    shared FunctionScope functionScope(FunctionModel model)
        => push(FunctionScope(model, pop));
    shared InterfaceScope interfaceScope(InterfaceModel model)
        => push(InterfaceScope(model, pop));

    "Get a declaration from the language package"
    shared DeclarationModel getLanguageDeclaration(String name)
        => languagePackage.getDirectMember(name, null, false);

    "Get a value from the root of the language module."
    shared Ptr<I64Type> getLanguageValue(String name)
        => scope.callI64(getterName(getLanguageDeclaration(name)));

    shared class Iteration(Node iteratedNode) {
        assert(is FunctionModel iteratorGetter
                = termGetMember(iteratedNode, "iterator"));
        value iteratorNext =
            iteratorGetter.type.declaration.getDirectMember("next", null, false);

        assert(is TypeDeclaration iterableTypeDeclaration =
            languagePackage.getDirectMember("Iterable", null, false));
        value iteratedAsInterface =
            termGetType(iteratedNode).getSupertype(iterableTypeDeclaration);
        assert(exists param = iterableTypeDeclaration.typeParameters.get(0));
        assert(exists et = iteratedAsInterface.typeArguments[param]);

        shared TypeModel elementType = et;

        shared Ptr<I64Type> iterator = scope.callI64(
                termGetMemberName(iteratedNode, "iterator"),
                iteratedNode.transform(expressionTransformer));

        shared Ptr<I64Type> getNext()
            => scope.callI64(declarationName(iteratorNext),
                iterator);
    }

}
