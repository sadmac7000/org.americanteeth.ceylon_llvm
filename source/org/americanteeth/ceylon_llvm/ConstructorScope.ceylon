import org.eclipse.ceylon.model.typechecker.model {
    ClassModel=Class
}

import ceylon.interop.java {
    CeylonIterable
}

"Floor value for constructor function priorities. We use this just to be well
 out of the way of any C libraries that might get linked with us."
Integer constructorPriorityOffset = 65536;

[LLVMType*] constructorArgumentTypes(ClassModel model)
    => (if (!model.toplevel)
        then [ptr(i64), ptr(i64)]
        else [ptr(i64)])
       .append(parameterListToLLVMTypes(model.parameterList));

"Scope of a class body"
class ConstructorScope(LLVMModule mod, ClassModel model,
            Anything(Scope) destroyer)
        extends CallableScope(mod, model,
                llvmFunction(mod, initializerName(model), null,
                    constructorArgumentTypes(model)),
                destroyer) {
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

    "The allocation offset for this item"
    shared actual I64 getAllocationOffset(Integer slot, AnyLLVMFunction func) {
        value shift = if (exists parent)
            then func.load(func.global(i64, sizeName(parent)))
            else I64Lit(0);
        value ret = func.add(shift, slot);
        return ret;
    }

    "Our direct-call constructor that allocates the new object with malloc"
    LLVMDeclaration directConstructor() {
        value fullParameters = body.arguments.rest.collect((x) => x.type);
        value directConstructor = llvmFunction(llvmModule,
                declarationName(model), ptr(i64), fullParameters);
        value size = directConstructor.load(directConstructor.global(i64,
                sizeName(model)));
        value bytes = directConstructor.mul(size, 8);

        value frame = directConstructor.call(ptr(i64),
                "malloc", bytes);
        directConstructor.mark(frameName, frame);

        value vt = directConstructor.toI64(
            directConstructor.load(directConstructor.global(ptr(i64),
                    vtableName(model))));
        directConstructor.store(frame, vt, I64Lit(1));

        directConstructor.callVoid(initializerName(model), *body.arguments);

        directConstructor.ret(frame);

        return directConstructor;
    }

    shared actual default {LLVMDeclaration*} results {
        let ([setupFunction, interfaceResolver, *positions]
                = vtSetupFunction(llvmModule, model));

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
