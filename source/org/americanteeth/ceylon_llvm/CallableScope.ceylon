import org.eclipse.ceylon.model.typechecker.model {
    ValueModel=Value,
    DeclarationModel=Declaration,
    InterfaceModel=Interface,
    SetterModel=Setter,
    ClassOrInterfaceModel=ClassOrInterface
}

abstract class CallableScope(LLVMModule mod, DeclarationModel model,
        String(DeclarationModel) namer, Anything(Scope) destroyer)
        extends Scope(mod, destroyer) {
    shared actual
        default LLVMFunction<PtrType<I64Type>?,[PtrType<I64Type>*]> body
            = LLVMFunction(mod, namer(model), ptr(i64),
                if (!model.toplevel)
                then [ptr(i64)]
                else []);

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
class GetterScope(LLVMModule mod, ValueModel model,
            Anything(Scope) destroyer)
        extends CallableScope(mod, model, getterDispatchName, destroyer) {}

"Scope of a setter method"
class SetterScope(LLVMModule mod, SetterModel model,
            Anything(Scope) destroyer)
        extends CallableScope(mod, model, setterDispatchName, destroyer) {
    shared actual LLVMFunction<PtrType<I64Type>,
    [PtrType<I64Type>]|[PtrType<I64Type>*]> body
            = LLVMFunction(mod, setterDispatchName(model), ptr(i64),
                if (!model.toplevel)
                then [ptr(i64), ptr(i64)]
                else [ptr(i64)]);
}
