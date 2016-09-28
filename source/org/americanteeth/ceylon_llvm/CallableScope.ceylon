import com.redhat.ceylon.model.typechecker.model {
    ValueModel=Value,
    DeclarationModel=Declaration
}

abstract class CallableScope(DeclarationModel model, String namePostfix = "")
        extends Scope() {
    shared actual default LLVMFunction body
            = LLVMFunction(declarationName(model) + namePostfix, ptr(i64), "",
                if (!model.toplevel)
                then [val(ptr(i64), "%.context")]
                else []);

    shared actual Ptr<I64Type>? getFrameFor(DeclarationModel declaration) {
        if (is ValueModel declaration, allocates(declaration)) {
            return body.register(ptr(i64), ".frame");
        }

        if (declaration.toplevel) {
            return null;
        }

        value container = declaration.container;

        if (container == model) {
            return body.register(ptr(i64), ".frame");
        }

        variable Anything visitedContainer = model.container;
        variable Ptr<I64Type> context = body.register(ptr(i64), ".context");

        while (is DeclarationModel v = visitedContainer, v != container) {
            context = body.toPtr(body.load(context), i64);
            visitedContainer = v.container;
        }

        "We should always find a parent scope. We'll get to a 'Package' if we
         don't"
        assert (container is DeclarationModel);

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