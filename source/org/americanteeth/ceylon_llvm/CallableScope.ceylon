import com.redhat.ceylon.model.typechecker.model {
    ValueModel=Value,
    InterfaceModel=Interface,
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

        if (!model.\iformal) {
            body.block = body.newBlock();
            body.entryPoint = body.block;
        } else {
            "Formal methods should not contain code."
            assert (block == entryPoint);
        }

        if (model.\iformal || model.\idefault) {
            value vtable = body.toPtr(body.load(body.register(ptr(i64),
                        ".context"), I64Lit(1)), i64);

            Label newHead;
            Ptr<I64Type>? expectedVt;

            variable value refined = model;

            while (refined.refinedDeclaration != refined) {
                refined = refined.refinedDeclaration;
            }

            if (model.\idefault || refined.container is InterfaceModel) {
                expectedVt =
                    body.load(body.global(ptr(i64),
                            "``declarationName(model.container)``$vtable"));
            } else {
                expectedVt = null;
            }

            if (model.\idefault) {
                assert(exists expectedVt);
                value dispatchCond = body.compareEq(expectedVt, vtable);
                value next = body.newBlock();
                newHead = body.newBlock();
                body.branch(dispatchCond, newHead, next);
                body.block = next;
            } else {
                newHead = block;
            }

            I64 position;

            if (refined.container is InterfaceModel) {
                assert(exists expectedVt);
                value interfaceResolver = body.toPtr(body.load(vtable,
                            interfaceResolverPosition), interfaceResolverType);
                value relativePosition = body.load(body.global(i64,
                        "``declarationName(refined)``$vtPosition"));
                value tableStart = body.callPtr(interfaceResolver, expectedVt);
                assert(exists tableStart);
                position = body.add(relativePosition, tableStart);
            } else {
                position = body.load(body.global(i64,
                        "``declarationName(refined)``$vtPosition"));
            }

            value jumpTarget = body.toPtr(body.load(vtable, position),
                body.llvmType);

            assert (is LLVMValue<LLVMType> ret =
                    body.tailCallPtr(jumpTarget, *body.arguments));
            body.ret(ret);
            body.block = newHead;

            if (model.\iformal) {
                return;
            }
        }

        if (allocatedBlocks==0 && model.toplevel) {
            body.assignTo(".frame").bitcast(llvmNull, ptr(i64));
            body.jump(entryPoint);
            body.block = block;
            return;
        }

        value blocksTotal =
            if (!model.toplevel)
            then allocatedBlocks + 1
            else allocatedBlocks;
        value bytesTotal = blocksTotal * 8;

        body.assignTo(".frame").call(ptr(i64), "malloc", I64Lit(bytesTotal));

        if (!model.toplevel) {
            body.store(body.register(ptr(i64), ".frame"),
                body.toI64(body.register(ptr(i64), ".context")));
        }

        body.jump(entryPoint);
        body.block = block;
    }
}

"Scope of a getter method"
class GetterScope(ValueModel model) extends CallableScope(model, "$get") {}

"Scope of a setter method"
class SetterScope(ValueModel model) extends CallableScope(model, "$set") {}
