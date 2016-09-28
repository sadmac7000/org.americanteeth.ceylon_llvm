import com.redhat.ceylon.model.typechecker.model {
    ClassModel=Class
}

import ceylon.interop.java {
    CeylonIterable
}

"Floor value for constructor function priorities. We use this just to be well
 out of the way of any C libraries that might get linked with us."
Integer constructorPriorityOffset = 65536;

"Scope of a class body"
class ConstructorScope(ClassModel model) extends CallableScope(model, "$init") {
    value parent = model.extendedType.declaration;
    shared actual void initFrame() {}

    "Our vtPosition variables that store the vtable offsets in the binary"
    {AnyLLVMGlobal*} vtPositions = CeylonIterable(model.members)
        .select((x) => (x.\iformal || x.\idefault) && !x.\iactual)
        .map((x) => LLVMGlobal("``declarationName(x)``$vtPosition", I64Lit(0)));

    "Global variables that se up the vtable"
    {LLVMDeclaration+} globals = [
        LLVMGlobal("``declarationName(model)``$vtSize", I64Lit(0)),
        LLVMGlobal(declarationName(model) + "$vtable", llvmNull),
        LLVMGlobal("``declarationName(model)``$size", I64Lit(0))
    ];

    "Constructor arguments."
    [AnyLLVMValue*] arguments {
        value prepend =
            if (!model.toplevel)
            then [val(ptr(i64), "%.context"), val(ptr(i64), "%.frame")]
            else [val(ptr(i64), "%.frame")];

        return prepend.chain(parameterListToLLVMValues(model.parameterList))
            .sequence();
    }

    shared actual LLVMFunction body
            = LLVMFunction(declarationName(model) + "$init", null, "",
                arguments);


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

    shared actual default {LLVMDeclaration*} results {
        value [setupFunction, interfaceResolver, *positions] = vtSetupFunction(model);

        assert (exists priority = declarationOrder[model]);
        setupFunction.makeConstructor(priority + constructorPriorityOffset);

        value sizeGlobal = setupFunction.global(i64,
                "``declarationName(model)``$size");
        value parentSize = setupFunction.loadGlobal(i64,
                "``declarationName(parent)``$size");
        value size = setupFunction.add(parentSize, allocatedBlocks);
        setupFunction.store(sizeGlobal, size);

        return super.results
            .chain { setupFunction, interfaceResolver, directConstructor() }
            .chain(vtPositions)
            .chain(positions)
            .chain(globals);
    }
}