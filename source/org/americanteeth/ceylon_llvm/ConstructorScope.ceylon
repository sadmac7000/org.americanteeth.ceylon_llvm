import com.redhat.ceylon.model.typechecker.model {
    ClassModel=Class
}

"Scope of a class body"
class ConstructorScope(ClassModel model) extends VTableScope(model) {
    value parent = model.extendedType.declaration;
    shared actual void initFrame() {}

    [AnyLLVMValue*] arguments {
        value prepend =
            if (!model.toplevel)
            then [val(ptr(i64), "%.context"), val(ptr(i64), "%.frame")]
            else [val(ptr(i64), "%.frame")];

        return prepend.chain(parameterListToLLVMValues(
                model.parameterList)).sequence();
    }

    shared actual LLVMFunction body
            = LLVMFunction(declarationName(model) + "$init", null, "",
                arguments);

    LLVMDeclaration sizeGlobal = LLVMGlobal("``declarationName(model)``$size",
            I64Lit(0));

    "The allocation offset for this item"
    shared actual I64 getAllocationOffset(Integer slot, LLVMFunction func) {
        value parent = model.extendedType.declaration;

        value shift = func.load(func.global(i64,
                "``declarationName(parent)``$size"));
        value ret = func.add(shift, slot);
        return ret;
    }

    "Our direct-call constructor that allocates the new object with malloc"
    LLVMDeclaration directConstructor() {
        value directConstructor = LLVMFunction(declarationName(model), ptr(i64
            ),
            "", parameterListToLLVMValues(model.parameterList));
        value size = directConstructor.load(directConstructor.global(i64,
                "``declarationName(model)``$size"));
        value bytes = directConstructor.mul(size, 8);

        directConstructor.assignTo(".frame").call(ptr(i64), "malloc", bytes);

        value vt = directConstructor.toI64(
            directConstructor.load(directConstructor.global(ptr(i64),
                    "``declarationName(model)``$vtable")));
        directConstructor.store(directConstructor.register(ptr(i64), ".frame"),
            vt, I64Lit(1));

        directConstructor.callVoid("``declarationName(model)``$init",
            *arguments);

        directConstructor.ret(directConstructor.register(ptr(i64), ".frame"));

        return directConstructor;
    }

    shared actual void additionalSetup(LLVMFunction setupFunction) {
        value sizeGlobal = setupFunction.global(i64,
            "``declarationName(model)``$size");
        value parentSize = setupFunction.load(setupFunction.global(i64,
                "``declarationName(parent)``$size"));
        value size = setupFunction.add(parentSize, allocatedBlocks);
        setupFunction.store(sizeGlobal, size);

    }

    shared actual {LLVMDeclaration*} results
        => super.results.chain{ sizeGlobal, directConstructor() };
}
