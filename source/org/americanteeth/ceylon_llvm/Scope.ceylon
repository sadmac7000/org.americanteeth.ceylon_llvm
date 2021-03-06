import ceylon.collection {
    ArrayList,
    HashMap
}

import org.eclipse.ceylon.model.typechecker.model {
    FunctionOrValueModel=FunctionOrValue,
    DeclarationModel=Declaration
}

"A scope containing instructions"
abstract class Scope(shared LLVMModule llvmModule,
        AnyLLVMFunction? bodyFunc, Anything(Scope) destroyer)
    of CallableScope | UnitScope | InterfaceScope
        satisfies Obtainable {

    shared AnyLLVMFunction body {
        "Interfaces don't have a body."
        assert(exists bodyFunc);
        return bodyFunc;
    }

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

    shared Integer allocatedBlocks => allocationBlock;

    "Is there an allocation for this value in the frame for this scope"
    shared Boolean allocates(FunctionOrValueModel v) => allocations.defines(v);

    "Get the context variable for a nested declaration"
    shared default Ptr<I64Type>? getContextFor(DeclarationModel declaration,
            Boolean sup = false)
            => null;

    "Get the frame variable for a nested declaration"
    shared default Ptr<I64Type>? getFrameFor(DeclarationModel declaration)
            => null;

    "The allocation offset for this item"
    shared default I64 getAllocationOffset(Integer slot, AnyLLVMFunction func)
            => I64Lit(slot + 1);

    "Add instructions to store an allocated element"
    LLVMFunction<PtrType<I64Type>, PtrType<I64Type>[2]>
            setterFor(FunctionOrValueModel model) {
        assert (exists slot = allocations[model]);

        value setter = llvmFunction(llvmModule, setterDispatchName(model),
                ptr(i64), [ptr(i64), ptr(i64)]);

        value offset = getAllocationOffset(slot, setter);

        assert(is Ptr<I64Type> contextReg = setter.arguments[0]);
        assert(is Ptr<I64Type> valueReg = setter.arguments[1]);
        value packedValue = setter.toI64(valueReg);

        setter.store(contextReg, packedValue, offset);

        return setter;
    }

    "Add instructions to fetch an allocated element"
    LLVMFunction<PtrType<I64Type>, [PtrType<I64Type>]>
            getterFor(FunctionOrValueModel model) {
        assert (exists slot = allocations[model]);

        value getter = llvmFunction(llvmModule, getterDispatchName(model),
                ptr(i64), [ptr(i64)]);

        value offset = getAllocationOffset(slot, getter);
        assert(is Ptr<I64Type> contextReg = getter.arguments.first);

        getter.ret(getter.toPtr(getter.load(contextReg, offset), i64));

        return getter;
    }

    shared formal Boolean owns(DeclarationModel d);

    "Create space in this scope for a value"
    shared default void allocate(FunctionOrValueModel declaration,
        Ptr<I64Type>? startValue) {
        if (!declaration.captured && !declaration.\ishared) {
            if (exists startValue) {
                body.mark(declaration, startValue);
            }

            return;
        }

        if (declaration.\iformal) {
            return;
        }

        if (allocations.defines(declaration)) {
            if (exists startValue) {
                store(declaration, startValue);
            }
            return;
        }

        value newPosition = allocationBlock++;
        allocations.put(declaration, newPosition);

        if (exists startValue) {
            value slotOffset = getAllocationOffset(newPosition, body);

            assert(exists frame = body.getMarked(ptr(i64), frameName));
            body.store(frame, body.toI64(startValue), slotOffset);
        }

        getterFor(declaration);

        if (declaration.\ivariable) {
            setterFor(declaration);
        }
    }

    "Access a declaration"
    shared Ptr<I64Type> load(DeclarationModel declaration) {
        /* TODO: Support yet weirder values here */
        if (! is FunctionOrValueModel declaration) {
            return llvmNull;
        }

        if (exists marked = body.getMarked(ptr(i64), declaration)) {
            return marked;
        }

        return callI64(getterName(declaration),
            *{ getContextFor(declaration) }.coalesced);
    }

    shared void store(FunctionOrValueModel declaration, Ptr<I64Type> val) {
        if (body.updateMark(declaration, val)) {
            return;
        }

        callI64(setterName(declaration),
            *{ getContextFor(declaration), val }.coalesced);
    }

    "Call a function returning a pointer to I64."
    shared Ptr<I64Type> callI64(String name, AnyLLVMValue* args)
        => body.call(ptr(i64), name, *args);

    "Add a vtable entry for the given declaration model"
    shared default void vtableEntry(DeclarationModel d) {
        "Scope does not cotain a vtable"
        assert (false);
    }

    shared default void finalize() {}

    shared actual void obtain() {}
    shared actual void release(Throwable? exc) {
        finalize();
        destroyer(this);
    }

}
