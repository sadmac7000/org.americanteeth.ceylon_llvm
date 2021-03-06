import org.bytedeco.javacpp {
    LLVM {
        LLVMValueRef,
        LLVMBasicBlockRef
    }
}

import ceylon.collection {
    ArrayList,
    HashSet,
    HashMap
}

"Type of entries in the constructor list."
StructType<[I32Type,PtrType<FuncType<Null,[]>>]> constructorType
    = StructType([i32,ptr(FuncType<Null,[]>(null,[]))]);

"An LLVM function declaration."
LLVMFunction<Ret,Args> llvmFunction<out Ret, in Args>(
    LLVMModule llvmModule,
    String name,
    Ret&LLVMType? returnType,
    Args argumentTypes)
        given Args satisfies [LLVMType*] {
    value ft = FuncType(returnType, argumentTypes);
    value ref = llvmModule.refForFunction(name, ft);

    return LLVMFunction(llvmModule, name, returnType, argumentTypes, ft, ref);
}

"Add an inheritance layer so we can intercept arguments."
class LLVMFunction<out Ret, in Args>(
    shared LLVMModule llvmModule,
    shared String name,
    shared Ret&LLVMType? returnType,
    Args argumentTypes,
    FuncType<Ret,Args> ty,
    LLVMValueRef funcRef)
        extends Ptr<FuncType<Ret,Args>>(ptr(ty), funcRef)
        given Args satisfies [LLVMType*] {
    "Full LLVM type of this function"
    shared AnyLLVMFunctionType llvmType = FuncType(returnType, argumentTypes);

    "Memoization for arguments"
    variable [AnyLLVMValue*]? arguments_ = null;

    "Whether makeConstructor has been called."
    variable value isConstructor = false;

    "Make this function a constructor (In the LLVM/system linker sense)."
    shared void makeConstructor(Integer priority) {
        "Should not call makeConstructor twice"
        assert(! isConstructor);
        isConstructor = true;

        value entry = llvm.constStruct([I32Lit(priority).ref,funcRef], false);
        llvmModule.appendGlobalArray(constructorType,
                "llvm.global_ctors", LLVMValue(constructorType, entry));
    }

    "Counter for auto-generated names"
    variable value nextTemporary = 0;

    "Auto-generated temporary name"
    String tempName() => "v``nextTemporary++``";

    "List of marks in this function."
    value marks = HashSet<Object>();

    /* TODO: call dispose on this eventually */
    "Our LLVM Instruction builder"
    value llvmBuilder = llvm.createBuilder();

    "An LLVM logical block."
    class Block() {
        "Our LLVM lib reference for this block."
        shared LLVMBasicBlockRef ref =
            llvm.appendBasicBlock(funcRef, tempName());

        "The jump label at the start of this block."
        shared Label label = Label(labelType, llvm.basicBlockAsValue(ref));

        "Marked values."
        value marks = HashMap<Object,AnyLLVMValue>();

        "Blocks that jump to this block."
        value predecessors = HashSet<AnyLLVMFunction.Block>();

        "Phi'd values."
        value phis = HashMap<Object,AnyLLVMValue>();

        "If the given key is marking the value `old` point it to `val`"
        shared void replaceMark(Object key, AnyLLVMValue old,
                AnyLLVMValue val) {
            if (exists m = marks[key], m == old) {
                marks[key] = val;
            }
        }

        "Mark that another block jumps to this block."
        shared void addPredecessor(AnyLLVMFunction.Block predecessor) {
            if (predecessor in predecessors) {
                return;
            }

            for (key->phi in phis) {
                llvm.addIncoming(phi.ref,
                        [predecessor.getMarked(phi.type, key).ref],
                        [predecessor.ref]);
            }

            predecessors.add(predecessor);
        }

        "Whether we've had a terminating instruction yet"
        shared Boolean terminated => llvm.getBasicBlockTerminator(ref) exists;

        "Mark a value in this block."
        shared void mark(Object key, AnyLLVMValue val) {
            assert(!terminated);
            marks[key] = val;
        }

        "Get a previously marked value from this block."
        shared LLVMValue<T> getMarked<T>(T t, Object key)
                given T satisfies LLVMType {
            if (exists m = marks[key]) {
                "Mark should be retrieved with the same type it was set as."
                assert(m.type == t);

                if (is LLVMValue<T> m) {
                    return m;
                }

                value replace = LLVMValue(t, m.ref);
                marks[key] = replace;
                return replace;
            }

            llvm.positionBuilder(llvmBuilder, ref,
                    llvm.getFirstInstruction(ref));
            value phi = LLVMValue(t, llvm.buildPhi(llvmBuilder,
                        t.ref, tempName()));
            llvm.positionBuilder(llvmBuilder, ref);

            marks[key] = phi;
            phis[key] = phi;

            value predecessorRefs = predecessors.collect((x) => x.ref);
            value predecessorVals = predecessors.collect(
                    (x) => x.getMarked(t, key).ref);

            llvm.addIncoming(phi.ref, predecessorVals, predecessorRefs);

            return phi;
        }

        "Mark that we've had a terminating instruction."
        shared void terminate({AnyLLVMFunction.Block*} successors) {
            for (successor in successors) {
                successor.addPredecessor(this);
            }
        }
    }

    "The logical block we are currently adding instructions to."
    variable value currentBlock = Block();

    llvm.positionBuilder(llvmBuilder, currentBlock.ref);

    "Instructions in the body of this function that perform the main business
     logic."
    value blocks = ArrayList { currentBlock };

    "Label for the block we are currently adding instructions to."
    shared Label block => currentBlock.label;

    "Find a block by its label"
    Block? findBlock(Label label)
        => blocks.select((x) => x.label == label).first;

    shared Boolean blockTerminated(Label which = currentBlock.label) {
        "Label must match a block in this function"
        assert(exists whichBlock = findBlock(which));
        return whichBlock.terminated;
    }

    "Switch to an existing block."
    assign block {
        value candidates = blocks.select((x) => x.label == block);

        "Label should match exactly one block."
        assert (candidates.size == 1);

        assert (exists newBlock = candidates.first);

        currentBlock = newBlock;
        llvm.positionBuilder(llvmBuilder, currentBlock.ref);
    }

    "Start adding instructions to the beginning of the function"
    shared void beginPrepending() {
        assert(exists block = llvm.getEntryBasicBlock(funcRef));
        value inst = llvm.getFirstInstruction(block);
        llvm.positionBuilder(llvmBuilder, block, inst);
    }

    "Move the insertion cursor to the given block and instruction"
    shared void moveCursor(Label lbl, variable Integer index) {
        assert(exists value bl = findBlock(lbl));
        variable LLVMValueRef? inst = llvm.getFirstInstruction(bl.ref);

        while (index > 0, exists i = inst) {
            inst = llvm.getNextInstruction(i);
            index -= 1;
        }
        llvm.positionBuilder(llvmBuilder, bl.ref, inst);
    }

    "Change a mark in this block and any other blocks that match it.
     Replace uses of the marked value with the new value and delete the old
     instruction."
    shared void replaceMark(Object marker, AnyLLVMValue val) {
        assert(exists old = getMarked(val.type, marker));

        for (block in blocks) {
            block.replaceMark(marker, old, val);
        }

        llvm.replaceAllUsesWith(old.ref, val.ref);
        llvm.instructionEraseFromParent(old.ref);
    }

    "Create a new block. Return the raw block."
    Block newBlockIntern() {
        value newBlock = Block();
        blocks.add(newBlock);
        return newBlock;
    }

    "Create a new block."
    shared Label newBlock() => newBlockIntern().label;

    "Split the current block at the insert position. In essence, insert a label
     at the current position."
    shared Label splitBlock() {
        if (! llvm.getFirstInstruction(currentBlock.ref) exists) {
            return block;
        }

        value ret = newBlockIntern();

        if (! currentBlock.terminated) {
            /* TODO: Reassess whether this is an error */
            jump(ret.label);
        }

        currentBlock = ret;
        llvm.positionBuilder(llvmBuilder, ret.ref);
        return ret.label;
    }

    "Mark a value in this block to track variable definitions."
    shared void mark(Object key, AnyLLVMValue val) {
        marks.add(key);
        currentBlock.mark(key, val);
    }

    "Update a mark only if it exists already. Return whether it did."
    shared Boolean updateMark(Object key, AnyLLVMValue val) {
        if (! key in marks) {
            return false;
        }

        mark(key, val);
        return true;
    }

    "Get a value that was marked in the current block. Use phi nodes to resolve
     conflicting marks. Phi nodes are inserted later, so don't worry about
     having topology right before calling."
    shared LLVMValue<T>? getMarked<T>(T type, Object key)
            given T satisfies LLVMType {
        if (! key in marks) {
            return null;
        }

        return currentBlock.getMarked<T>(type, key);
    }

    "Access a global from this function"
    shared Ptr<T> global<T>(T t, String name) given T satisfies LLVMType
        => llvmModule.lookupGlobal(t, name);

    "Emit a call instruction for a function pointer"
    LLVMValue<R>|<R&Null> doCallPtr<R>(Boolean tail,
            Ptr<FuncType<R,Nothing>> func, AnyLLVMValue* args) {
        value call = llvm.buildCall(llvmBuilder, func.ref,
                args.collect((x) => x.ref), tempName());

        if (tail) {
            llvm.setTailCall(call, true);
        }

        if (exists r = func.type.targetType.returnType) {
            return LLVMValue(r, call);
        }

        assert(is R&Null n = null);
        return n;
    }

    "Emit a call instruction for a function pointer"
    shared LLVMValue<R>|<R&Null> callPtr<R>(Ptr<FuncType<R,Nothing>> func,
            AnyLLVMValue* args)
        => doCallPtr(false, func, *args);

    "Emit a call instruction for a function pointer"
    shared void tailCallPtr(Ptr<AnyLLVMFunctionType> func, AnyLLVMValue* args)
        => ret(doCallPtr(true, func, *args));

    "Emit a call instruction"
    shared LLVMValue<T>|<T&Null> call<T>(T&LLVMType? type, String name,
                AnyLLVMValue* args)
        => callPtr(llvmModule.lookupGlobal(
                    FuncType(type, args.collect((x) => x.type)), name),
                *args);

    "Add a return statement to this block"
    shared void ret<T>(LLVMValue<T>? val) given T satisfies LLVMType {
        llvm.buildRet(llvmBuilder, val?.ref);
        currentBlock.terminate({});
    }

    "Add a bitwise or instruction."
    shared LLVMValue<T> or<T>(T type, LLVMValue<T> a, LLVMValue<T> b)
            given T satisfies LLVMType
        => LLVMValue(type, llvm.buildOr(llvmBuilder, a.ref, b.ref, tempName()));

    "Add an 'unreachable' instruction."
    shared void unreachable() {
        llvm.buildUnreachable(llvmBuilder);
        currentBlock.terminate({});
    }

    LLVMValueRef asI64Ref(I64|Integer val)
        => if (is Integer val) then I64Lit(val).ref else val.ref;

    "Add an add instruction to this block"
    shared I64 add(I64|Integer a, I64|Integer b)
        => LLVMValue(i64, llvm.buildAdd(llvmBuilder,
                    asI64Ref(a), asI64Ref(b), tempName()));

    "Add a mul instruction to this block"
    shared I64 mul(I64|Integer a, I64|Integer b)
        => LLVMValue(i64, llvm.buildMul(llvmBuilder,
                    asI64Ref(a), asI64Ref(b), tempName()));

    "Offset a pointer"
    shared Ptr<T> offset<T>(Ptr<T> ptr, I64 amount)
            given T satisfies LLVMType
        => LLVMValue(ptr.type, llvm.buildGEP(llvmBuilder, ptr.ref, [amount.ref],
                    tempName()));

    "Load from a pointer"
    shared LLVMValue<T> load<T>(Ptr<T> ptr, I64? off = null)
            given T satisfies LLVMType
        => if (exists off)
           then load(offset(ptr, off))
           else LLVMValue(ptr.type.targetType,
                   llvm.buildLoad(llvmBuilder, ptr.ref, tempName()));

    "Load from a global variable."
    shared LLVMValue<T> loadGlobal<T>(T t, String name)
            given T satisfies LLVMType
        => load(global(t, name));

    "Store to a pointer."
    shared void store<T>(Ptr<T> ptr, LLVMValue<T> val, I64? off = null)
            given T satisfies LLVMType {
        if (exists off) {
           store(offset(ptr, off), val);
        } else {
            llvm.buildStore(llvmBuilder, val.ref, ptr.ref);
        }
    }

    "Store to a global variable."
    shared void storeGlobal<T>(String name, LLVMValue<T> val)
            given T satisfies LLVMType
        => store(global(val.type, name), val);

    "Cast an I64 to a Ptr<I64>"
    shared Ptr<T> toPtr<T>(I64 p, T t)
            given T satisfies LLVMType
        => LLVMValue(ptr(t), llvm.buildIntToPtr(llvmBuilder, p.ref, ptr(t).ref,
                    tempName()));

    "Cast a Ptr<I64> to an I64"
    shared I64 toI64<T>(Ptr<T> p) given T satisfies LLVMType
        => LLVMValue(i64, llvm.buildPtrToInt(llvmBuilder, p.ref, i64.ref,
                    tempName()));

    "Compare two values and see if they are equal."
    shared I1 compareEq<T>(T a, T b)
            given T satisfies AnyLLVMValue
        => LLVMValue(i1, llvm.buildICmp(llvmBuilder, LLVMIntPredicate.intEQ,
                    a.ref, b.ref, tempName()));

    "Compare two values and see if they are not equal."
    shared I1 compareNE<T>(T a, T b)
            given T satisfies AnyLLVMValue
        => LLVMValue(i1, llvm.buildICmp(llvmBuilder, LLVMIntPredicate.intNE,
                    a.ref, b.ref, tempName()));

    "Return one of two values based on a truth value"
    shared LLVMValue<T> select<T>(I1 selector, T type,
            LLVMValue<T> a, LLVMValue<T> b)
            given T satisfies LLVMType
        => LLVMValue(type, llvm.buildSelect(llvmBuilder, selector.ref,
                    a.ref, b.ref, tempName()));

    "Jump to the given label."
    shared void jump(Label l) {
        "Jump target should exist."
        assert(exists b = findBlock(l));
        llvm.buildBr(llvmBuilder, b.ref);
        currentBlock.terminate({b});
    }

    "Branch on the given conditional"
    shared Label[2] branch(I1 condition, Label? t_in = null,
            Label? f_in = null) {
        value t_in_block = if (exists t_in) then findBlock(t_in) else null;
        value f_in_block = if (exists f_in) then findBlock(f_in) else null;
        value t = t_in_block else newBlockIntern();
        value f = f_in_block else newBlockIntern();
        llvm.buildCondBr(llvmBuilder, condition.ref, t.ref, f.ref);
        currentBlock.terminate([t, f]);
        return [t.label, f.label];
    }

    "LLVM bitcast cast"
    shared LLVMValue<T> bitcast<T>(AnyLLVMValue v, T t)
            given T satisfies LLVMType
        => LLVMValue(t, llvm.buildBitCast(llvmBuilder, v.ref, t.ref,
                    tempName()));

    "Private linkage"
    shared Boolean private => llvm.getLinkage(ref) == llvm.privateLinkage;
    assign private
        => llvm.setLinkage(ref,
                private then llvm.privateLinkage else llvm.externalLinkage);

    "Argument values"
    shared [AnyLLVMValue*] arguments
        => arguments_ else argumentTypes.keys.collect((i) {
            assert(exists t = argumentTypes[i]);
            return t.instance(llvm.getParam(ref, i));
        });
}

"Any LLVM Function"
alias AnyLLVMFunction => LLVMFunction<Anything,Nothing>;
