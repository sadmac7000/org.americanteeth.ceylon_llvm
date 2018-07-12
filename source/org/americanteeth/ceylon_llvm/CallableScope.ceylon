import org.eclipse.ceylon.model.typechecker.model {
    ValueModel=Value,
    DeclarationModel=Declaration,
    FunctionModel=Function,
    InterfaceModel=Interface,
    SetterModel=Setter,
    ClassOrInterfaceModel=ClassOrInterface
}

import ceylon.interop.java {
    CeylonList
}

class CallableScope(LLVMModule mod, DeclarationModel model,
        AnyLLVMFunction bodyFunc, Anything(Scope) destroyer)
        extends Scope(mod, bodyFunc, destroyer) {
    value frame = bodyFunc.call(ptr(i64), "malloc", I64Lit(0));
    bodyFunc.mark(frameName, frame);

    shared actual Boolean owns(DeclarationModel d)
        => if (exists c = containingDeclaration(d), c == model)
            then true
            else false;

    "Return the frame pointer for the given declaration by starting from the
     current frame and following the context pointers."
    Ptr<I64Type>? climbContextStackTo(DeclarationModel container, Boolean sup) {
        if (model == container) {
            return body.getMarked(ptr(i64), frameName);
        }

        variable DeclarationModel? visitedContainer = containingDeclaration(model);
        assert(is Ptr<I64Type> start_context = body.arguments.first);
        variable Ptr<I64Type> context = start_context;

        function isMatch(DeclarationModel v)
            => if (sup || container is InterfaceModel)
               then v is ClassOrInterfaceModel
               else v == container;

        while (exists v = visitedContainer, !isMatch(v)) {
            context = body.toPtr(body.load(context), i64);
            visitedContainer = containingDeclaration(v);
        }

        "We should not climb out of the package"
        assert(visitedContainer exists);

        return context;
    }

    shared actual Ptr<I64Type>? getFrameFor(DeclarationModel container)
        => climbContextStackTo(container, false);

    shared actual Ptr<I64Type>? getContextFor(DeclarationModel declaration,
            Boolean sup) {
        if (is ValueModel declaration, allocates(declaration)) {
            return body.getMarked(ptr(i64), frameName);
        }

        value container = containingDeclaration(declaration);

        if (! is DeclarationModel container) {
            return null;
        }

        return climbContextStackTo(container, sup);
    }

    "Add instructions to initialize the frame object"
    shared actual default void initFrame() {
        value block = body.block;
        body.beginPrepending();

        value totalBlocks = if (!model.toplevel)
                            then allocatedBlocks + 1
                            else allocatedBlocks;

        if (totalBlocks == 0) {
            body.replaceMark(frameName, body.bitcast(llvmNull, ptr(i64)));
        } else {
            value entryBlock = body.block;
            value newFrame =
                body.call(ptr(i64), "malloc", I64Lit(totalBlocks * 8));
            body.replaceMark(frameName, newFrame);

            assert(is Ptr<I64Type> context = body.arguments.first);
            body.moveCursor(entryBlock, 1);

            if (!model.toplevel) {
                body.store(newFrame, body.toI64(context));
            }
        }

        body.block = block;
    }
}

"Scope of a getter method"
CallableScope makeGetterScope(LLVMModule mod, ValueModel model,
        Anything(Scope) destroyer)
    => CallableScope(mod, model,
        llvmFunction(mod, getterDispatchName(model), ptr(i64),
            if (!model.toplevel)
            then [ptr(i64)]
            else []),
        destroyer);

"Scope of a setter method"
CallableScope makeSetterScope(LLVMModule mod, SetterModel model,
        Anything(Scope) destroyer) {
    value func = llvmFunction(mod, setterDispatchName(model), ptr(i64),
            if (!model.toplevel)
            then [ptr(i64), ptr(i64)]
            else [ptr(i64)]);

    assert(exists reg = func.arguments.last);
    func.mark(model.parameter.name, reg);
    return CallableScope(mod, model, func, destroyer);
}

"Construct an LLVM function with the approprate signature for a given Ceylon
 function."
LLVMFunction<PtrType<I64Type>,[PtrType<I64Type>*]>
    llvmFunctionForCeylonFunction(LLVMModule mod, FunctionModel model,
        String(FunctionModel) namer = declarationName) {
    value ret = llvmFunction(mod, namer(model), ptr(i64),
            if (!model.toplevel)
            then parameterListToLLVMTypes(model.firstParameterList)
                    .withLeading(ptr(i64))
            else parameterListToLLVMTypes(model.firstParameterList));

    value args = ret.arguments;
    value names = CeylonList(model.firstParameterList.parameters)
        .collect((x) => x.name);

    [AnyLLVMValue*] mapArgs;

    if (args.size == names.size) {
        mapArgs = args;
    } else {
        mapArgs = args.rest;
        assert(exists ctx = args.first);
        ret.mark(contextName, ctx);
    }

    for ([name, arg] in zipPairs(names, mapArgs)) {
        ret.mark(name, arg);
    }

    return ret;
}

"The scope of a function"
CallableScope makeFunctionScope(LLVMModule mod, FunctionModel model,
        Anything(Scope) destroyer)
    => CallableScope(mod, model,
            llvmFunctionForCeylonFunction(mod, model, dispatchName), destroyer);
