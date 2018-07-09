import org.eclipse.ceylon.model.typechecker.model {
    ValueModel=Value,
    DeclarationModel=Declaration,
    FunctionModel=Function,
    InterfaceModel=Interface,
    SetterModel=Setter,
    ClassOrInterfaceModel=ClassOrInterface
}

class CallableScope(LLVMModule mod, DeclarationModel model,
        AnyLLVMFunction bodyFunc, Anything(Scope) destroyer)
        extends Scope(mod, bodyFunc, destroyer) {
    shared actual Boolean owns(DeclarationModel d)
        => if (exists c = containingDeclaration(d), c == model)
            then true
            else false;

    "Return the frame pointer for the given declaration by starting from the
     current frame and following the context pointers."
    Ptr<I64Type>? climbContextStackTo(DeclarationModel container, Boolean sup) {
        if (model == container) {
            return body.register(ptr(i64), frameName);
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
            return body.register(ptr(i64), frameName);
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
        value entryPoint = body.entryPoint;

        body.block = body.newBlock();

        value totalBlocks =
            if (!model.toplevel)
            then allocatedBlocks + 1
            else allocatedBlocks;

        if (totalBlocks == 0) {
            body.assignTo(frameName).bitcast(llvmNull, ptr(i64));
        } else {
            body.assignTo(frameName).call(ptr(i64), "malloc",
                    I64Lit(totalBlocks * 8));

            assert(is Ptr<I64Type> context = body.arguments.first);

            if (!model.toplevel) {
                body.store(body.register(ptr(i64), frameName),
                    body.toI64(context));
            }
        }

        body.jump(entryPoint);
        body.entryPoint = body.block;
        body.block = block;
    }
}

"Scope of a getter method"
CallableScope makeGetterScope(LLVMModule mod, ValueModel model,
        Anything(Scope) destroyer)
    => CallableScope(mod, model,
        LLVMFunction(mod, getterDispatchName(model), ptr(i64),
            if (!model.toplevel)
            then [ptr(i64)]
            else []),
        destroyer);

"Scope of a setter method"
CallableScope makeSetterScope(LLVMModule mod, SetterModel model,
        Anything(Scope) destroyer)
    => CallableScope(mod, model,
        LLVMFunction(mod, setterDispatchName(model), ptr(i64),
            if (!model.toplevel)
            then [ptr(i64), ptr(i64)]
            else [ptr(i64)]),
        destroyer);

"Construct an LLVM function with the approprate signature for a given Ceylon
 function."
LLVMFunction<PtrType<I64Type>,[PtrType<I64Type>*]>
    llvmFunctionForCeylonFunction(LLVMModule mod, FunctionModel model,
        String(FunctionModel) namer = declarationName)
    => LLVMFunction(mod, namer(model), ptr(i64),
                if (!model.toplevel)
                then parameterListToLLVMTypes(model.firstParameterList)
                         .withLeading(ptr(i64))
                else parameterListToLLVMTypes(model.firstParameterList));

"The scope of a function"
CallableScope makeFunctionScope(LLVMModule mod, FunctionModel model,
        Anything(Scope) destroyer)
    => CallableScope(mod, model,
            llvmFunctionForCeylonFunction(mod, model, dispatchName), destroyer);
