import com.redhat.ceylon.model.typechecker.model {
    ValueModel=Value,
    DeclarationModel=Declaration,
    InterfaceModel=Interface,
    ClassOrInterfaceModel=ClassOrInterface
}

abstract class CallableScope(DeclarationModel model, String namePostfix = "")
        extends Scope() {
    shared actual default LLVMFunction body
            = LLVMFunction(declarationName(model) + namePostfix, ptr(i64), "",
                if (!model.toplevel)
                then [val(ptr(i64), "%.context")]
                else []);

    shared actual Ptr<I64Type>? getFrameFor(DeclarationModel declaration,
            Boolean sup) {
        if (is ValueModel declaration, allocates(declaration)) {
            return body.register(ptr(i64), ".frame");
        }

        value container = declaration.container;

        if (! is DeclarationModel container) {
            return null;
        }

        if (model == container) {
            return body.register(ptr(i64), ".frame");
        }

        variable Anything visitedContainer = model.container;
        variable Ptr<I64Type> context = body.register(ptr(i64), ".context");

        function isMatch(DeclarationModel v)
            => if (sup || container is InterfaceModel)
               then v is ClassOrInterfaceModel
               else v == container;

        while (is DeclarationModel v = visitedContainer, !isMatch(v)) {
            context = body.toPtr(body.load(context), i64);
            visitedContainer = v.container;
        }

        "We should always find a parent scope. We'll get to a 'Package' if we
         don't"
        assert (visitedContainer is DeclarationModel);

        return context;
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
            body.assignTo(".frame").bitcast(llvmNull, ptr(i64));
        } else {
            body.assignTo(".frame").call(ptr(i64), "malloc",
                    I64Lit(totalBlocks * 8));

            if (!model.toplevel) {
                body.store(body.register(ptr(i64), ".frame"),
                    body.toI64(body.register(ptr(i64), ".context")));
            }
        }

        body.jump(entryPoint);
        body.entryPoint = body.block;
        body.block = block;
    }
}

"Scope of a getter method"
class GetterScope(ValueModel model) extends CallableScope(model, "$get") {}

"Scope of a setter method"
class SetterScope(ValueModel model) extends CallableScope(model, "$set") {}
