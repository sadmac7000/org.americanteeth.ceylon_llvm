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
class ConstructorScope(ClassModel model, Anything(Scope) destroyer)
        extends CallableScope(model, initializerName, destroyer) {
    value parent = model.extendedType?.declaration;
    shared actual void initFrame() {}

    "Our vtPosition variables that store the vtable offsets in the binary"
    {AnyLLVMGlobal*} vtPositions = CeylonIterable(model.members)
        .select((x) => (x.\iformal || x.\idefault) && !x.\iactual)
        .map((x) => LLVMGlobal(vtPositionName(x), I64Lit(0)));

    "Global variables that se up the vtable"
    {LLVMDeclaration+} globals = [
        LLVMGlobal(vtSizeName(model), I64Lit(0)),
        LLVMGlobal(vtableName(model), llvmNull),
        LLVMGlobal(sizeName(model), I64Lit(0))
    ];

    value basicParameters = parameterListToLLVMValues(model.parameterList);

    "Constructor arguments."
    [AnyLLVMValue*] arguments {
        value prepend =
            if (!model.toplevel)
            then [contextRegister, frameRegister]
            else [frameRegister];

        return prepend.append(basicParameters);
    }

    shared actual LLVMFunction body
            = LLVMFunction(initializerName(model), null, "", arguments);

    "The allocation offset for this item"
    shared actual I64 getAllocationOffset(Integer slot, LLVMFunction func) {
        value shift = if (exists parent)
            then func.load(func.global(i64, sizeName(parent)))
            else I64Lit(0);
        value ret = func.add(shift, slot);
        return ret;
    }

    "Our direct-call constructor that allocates the new object with malloc"
    LLVMDeclaration directConstructor() {
        value fullParameters = if (model.toplevel)
            then basicParameters
            else [contextRegister].append(basicParameters);
        value directConstructor = LLVMFunction(declarationName(model),
                ptr(i64), "", fullParameters);
        value size = directConstructor.load(directConstructor.global(i64,
                sizeName(model)));
        value bytes = directConstructor.mul(size, 8);

        value frame = directConstructor.assignTo(frameName).call(ptr(i64),
                "malloc", bytes);

        value vt = directConstructor.toI64(
            directConstructor.load(directConstructor.global(ptr(i64),
                    vtableName(model))));
        directConstructor.store(frame, vt, I64Lit(1));

        directConstructor.callVoid(initializerName(model), *arguments);

        directConstructor.ret(frame);

        return directConstructor;
    }

    shared actual default {LLVMDeclaration*} results {
        value [setupFunction, interfaceResolver, *positions] = vtSetupFunction(model);

        assert (exists priority = declarationOrder[model]);
        setupFunction.makeConstructor(priority + constructorPriorityOffset);

        value sizeGlobal = setupFunction.global(i64, sizeName(model));
        value parentSize = if (exists parent)
            then setupFunction.loadGlobal(i64, sizeName(parent))
            else I64Lit(0);
        value size = setupFunction.add(parentSize, allocatedBlocks);
        setupFunction.store(sizeGlobal, size);

        return super.results
            .chain { setupFunction, interfaceResolver, directConstructor() }
            .chain(vtPositions)
            .chain(positions)
            .chain(globals);
    }
}
