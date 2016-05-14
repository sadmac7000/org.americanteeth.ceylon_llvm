import ceylon.collection {
    ArrayList,
    HashMap,
    HashSet
}

import com.redhat.ceylon.model.typechecker.model {
    ValueModel=Value,
    DeclarationModel=Declaration
}

"A scope containing instructions"
abstract class Scope() of CallableScope | UnitScope {
    value getters = ArrayList<LLVMDeclaration>();
    value currentValues = HashMap<ValueModel,Ptr<I64Type>>();
    value allocations = HashMap<ValueModel,Integer>();
    variable value allocationBlock = 0;

    shared Integer allocatedBlocks => allocationBlock;

    shared HashSet<ValueModel> usedItems = HashSet<ValueModel>();

    "Is there an allocation for this value in the frame for this scope"
    shared Boolean allocates(ValueModel v) => allocations.defines(v);

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

        allocations.put(declaration, allocationBlock++);

        if (exists startValue) {
            /* allocationBlock = the new allocation position + 1 */
            value slotOffset = getAllocationOffset(allocationBlock - 1,
                body);

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

        usedItems.add(declaration);

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

"Scope of a getter method"
class GetterScope(ValueModel model) extends CallableScope(model, "$get") {}

"Scope of a setter method"
class SetterScope(ValueModel model) extends CallableScope(model, "$set") {}
