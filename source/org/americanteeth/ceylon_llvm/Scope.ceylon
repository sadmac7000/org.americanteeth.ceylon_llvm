import ceylon.collection {
    ArrayList,
    HashMap
}

import com.redhat.ceylon.model.typechecker.model {
    ValueModel=Value,
    DeclarationModel=Declaration
}

"A scope containing instructions"
abstract class Scope() of CallableScope | UnitScope | InterfaceScope {
    value getters = ArrayList<LLVMDeclaration>();
    value currentValues = HashMap<ValueModel,Ptr<I64Type>>();
    value allocations = HashMap<ValueModel,Integer>();
    variable value allocationBlock = 0;

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
    LLVMFunction getterFor(ValueModel model) {
        assert (exists slot = allocations[model]);

        value getter = LLVMFunction(declarationName(model) + "$get",
            ptr(i64), "", [val(ptr(i64), "%.context")]);

        value offset = getAllocationOffset(slot, getter);

        getter.ret(getter.toPtr(getter.load(getter.register(ptr(i64),
                        ".context"), offset), i64));

        return getter;
    }

    "Create space in this scope for a value"
    shared default void allocate(ValueModel declaration,
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
                body.register(ptr(i64), ".frame"),
                body.toI64(startValue),
                slotOffset);
        }

        getters.add(getterFor(declaration));
    }

    "Access a declaration"
    shared Ptr<I64Type> access(ValueModel declaration) {
        if (exists cached = currentValues[declaration]) {
            return cached;
        }

        return body.call(ptr(i64), "``declarationName(declaration)``$get",
            *{ getFrameFor(declaration) }.coalesced);
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
