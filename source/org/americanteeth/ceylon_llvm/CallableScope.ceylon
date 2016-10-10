import com.redhat.ceylon.model.typechecker.model {
    ValueModel=Value,
    DeclarationModel=Declaration,
    InterfaceModel=Interface,
    PackageModel=Package,
    FunctionOrValueModel=FunctionOrValue,
    ConstructorModel=Constructor,
    SetterModel=Setter,
    SpecificationModel=Specification,
    ClassOrInterfaceModel=ClassOrInterface
}

abstract class CallableScope(DeclarationModel model,
        String(DeclarationModel) namer, Anything(Scope) destroyer)
        extends Scope(destroyer) {
    shared actual default LLVMFunction body
            = LLVMFunction(namer(model), ptr(i64), "",
                if (!model.toplevel)
                then [contextRegister]
                else []);

    DeclarationModel? getContainer(DeclarationModel d) {
        variable value s = if (is SpecificationModel c = d.container)
           then c.declaration
           else d.container;

        while (! is DeclarationModel k = s) {
            if (is PackageModel k) {
                return null;
            }
            s = k.container;
        }

        assert(is DeclarationModel ret = s);

        if (is FunctionOrValueModel d,
                d.type.declaration is ConstructorModel) {
            return getContainer(ret);
        }

        if (is ValueModel d, !d.transient) {
            return getContainer(ret);
        }

        return ret;
    }

    "Return the frame pointer for the given declaration by starting from the
     current frame and following the context pointers."
    Ptr<I64Type>? climbContextStackTo(DeclarationModel container, Boolean sup) {
        if (model == container) {
            return body.register(ptr(i64), frameName);
        }

        variable DeclarationModel? visitedContainer = getContainer(model);
        variable Ptr<I64Type> context = body.register(ptr(i64), contextName);

        function isMatch(DeclarationModel v)
            => if (sup || container is InterfaceModel)
               then v is ClassOrInterfaceModel
               else v == container;

        while (exists v = visitedContainer, !isMatch(v)) {
            context = body.toPtr(body.load(context), i64);
            visitedContainer = getContainer(v);
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

        value container = getContainer(declaration);

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

            if (!model.toplevel) {
                body.store(body.register(ptr(i64), frameName),
                    body.toI64(body.register(ptr(i64), contextName)));
            }
        }

        body.jump(entryPoint);
        body.entryPoint = body.block;
        body.block = block;
    }
}

"Scope of a getter method"
class GetterScope(ValueModel model, Anything(Scope) destroyer)
        extends CallableScope(model, getterDispatchName, destroyer) {}

"Scope of a setter method"
class SetterScope(SetterModel model, Anything(Scope) destroyer)
        extends CallableScope(model, setterDispatchName, destroyer) {
    shared actual LLVMFunction body
            = LLVMFunction(setterDispatchName(model), ptr(i64), "",
                if (!model.toplevel)
                then [contextRegister, loc(ptr(i64), model.name)]
                else [loc(ptr(i64), model.name)]);
}
