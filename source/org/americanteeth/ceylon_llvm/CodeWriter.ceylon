import org.eclipse.ceylon.model.typechecker.model {
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
    shared formal LLVMModule llvmModule;

    shared CallableScope getterScope(ValueModel model)
        => push(makeGetterScope(llvmModule, model, pop));
    shared CallableScope setterScope(SetterModel model)
        => push(makeSetterScope(llvmModule, model, pop));
    shared ConstructorScope constructorScope(ClassModel model)
        => push(ConstructorScope(llvmModule, model, pop));
    shared CallableScope functionScope(FunctionModel model)
        => push(makeFunctionScope(llvmModule, model, pop));
    shared InterfaceScope interfaceScope(InterfaceModel model)
        => push(InterfaceScope(llvmModule, model, pop));

    "Get a declaration from the language package"
    shared DeclarationModel getLanguageDeclaration(String name)
        => languagePackage.getDirectMember(name, null, false);

    "Get a value from the root of the language module."
    shared Ptr<I64Type> getLanguageValue(String name)
        => scope.callI64(getterName(getLanguageDeclaration(name)));

    shared class Iteration(shared Ptr<I64Type> iterator,
            shared TypeModel iterableType) {
        assert(is FunctionModel iteratorGetter
                = iterableType.declaration.getMember("iterator", null, false));
        value iteratorNext =
            iteratorGetter.type.declaration.getDirectMember("next", null, false);

        assert(is TypeDeclaration iterableTypeDeclaration =
            languagePackage.getDirectMember("Iterable", null, false));
        value iteratedAsInterface =
            iterableType.getSupertype(iterableTypeDeclaration);
        assert(exists param = iterableTypeDeclaration.typeParameters.get(0));
        assert(exists et = iteratedAsInterface.typeArguments[param]);

        shared TypeModel elementType = et;

        shared Ptr<I64Type> getNext()
            => scope.callI64(declarationName(iteratorNext),
                iterator);
    }

    shared Iteration iterationForNode(Node n)
        => Iteration(n.transform(expressionTransformer), termGetType(n));
}
