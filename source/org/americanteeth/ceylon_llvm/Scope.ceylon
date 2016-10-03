import ceylon.collection {
    ArrayList,
    HashMap
}

import com.redhat.ceylon.model.typechecker.model {
    FunctionOrValueModel=FunctionOrValue,
    ValueModel=Value,
    DeclarationModel=Declaration
}

"A scope containing instructions"
abstract class Scope(Anything(Scope) destroyer)
    of CallableScope | UnitScope | InterfaceScope
        satisfies Obtainable {
    value getters = ArrayList<LLVMDeclaration>();
    value currentValues = HashMap<FunctionOrValueModel,Ptr<I64Type>>();
    value allocations = HashMap<FunctionOrValueModel,Integer>();
    variable value allocationBlock = 0;
    value loopContextStack = ArrayList<LoopContext>();

    "Information about loop we are inside of (break/continue points)."
    shared class LoopContext(shared Label continuePoint, shared Label breakPoint)
            satisfies Obtainable {
        shared actual void obtain() => loopContextStack.add(this);
        shared actual void release(Throwable? exc) {
            "LoopContext expects to pop itself on release."
            assert(exists l = loopContextStack.deleteLast(), l == this);
        }
    }

    "Break out of the current loop in this scope."
    shared void breakLoop() {
        assert(exists l = loopContextStack.last);
        body.jump(l.breakPoint);
    }

    "Continue the current loop in this scope."
    shared void continueLoop() {
        assert(exists l = loopContextStack.last);
        body.jump(l.continuePoint);
    }

    shared actual void obtain() {}
    shared actual void release(Throwable? exc) => destroyer(this);

    shared Integer allocatedBlocks => allocationBlock;

    "Is there an allocation for this value in the frame for this scope"
    shared Boolean allocates(ValueModel v) => allocations.defines(v);

    "Get the context variable for a nested declaration"
    shared default Ptr<I64Type>? getContextFor(DeclarationModel declaration,
            Boolean sup = false)
            => null;

    "Get the frame variable for a nested declaration"
    shared default Ptr<I64Type>? getFrameFor(DeclarationModel declaration)
            => null;

    "The allocation offset for this item"
    shared default I64 getAllocationOffset(Integer slot, LLVMFunction func)
            => I64Lit(slot + 1);

    "Add instructions to fetch an allocated element"
    LLVMFunction getterFor(FunctionOrValueModel model) {
        assert (exists slot = allocations[model]);

        value getter = LLVMFunction(getterName(model), ptr(i64), "",
                [loc(ptr(i64), ".context")]);

        value offset = getAllocationOffset(slot, getter);

        getter.ret(getter.toPtr(getter.load(getter.register(ptr(i64),
                        ".context"), offset), i64));

        return getter;
    }

    "Create space in this scope for a value"
    shared default void allocate(FunctionOrValueModel declaration,
        Ptr<I64Type>? startValue) {
        if (!declaration.captured && !declaration.\ishared) {
            if (exists startValue) {
                currentValues.put(declaration, startValue);
            }

            return;
        }

        value newPosition = allocationBlock++;
        allocations.put(declaration, newPosition);

        if (exists startValue) {
            value slotOffset = getAllocationOffset(newPosition, body);

            body.store(
                body.register(ptr(i64), frameName),
                body.toI64(startValue),
                slotOffset);
        }

        getters.add(getterFor(declaration));
    }

    "Access a declaration"
    shared Ptr<I64Type> access(FunctionOrValueModel declaration) {
        if (exists cached = currentValues[declaration]) {
            return cached;
        }

        return body.call(ptr(i64), getterName(declaration),
            *{ getContextFor(declaration) }.coalesced);
    }

    "Add a vtable entry for the given declaration model"
    shared default void vtableEntry(DeclarationModel d) {
        "Scope does not cotain a vtable"
        assert (false);
    }

    shared formal LLVMFunction body;
    shared default void initFrame() {}

    shared default {LLVMDeclaration*} results {
        initFrame();
        return { body, *getters };
    }
}
