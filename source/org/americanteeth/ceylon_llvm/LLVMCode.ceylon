import ceylon.collection {
    ArrayList,
    HashSet,
    HashMap
}

import ceylon.process {
    createProcess,
    currentError
}

import ceylon.file {
    Reader
}

"Any top-level declaration in an LLVM compilation unit."
abstract class LLVMDeclaration(shared String name) {
    shared default {<String->LLVMType>*} declarationsNeeded = {};
}

"Get the current LLVM version"
[Integer, Integer] getLLVMVersion() {
    value proc = createProcess {
        command = "/usr/bin/llvm-config";
        arguments = ["--version"];
        error = currentError;
    };

    proc.waitForExit();

    assert(is Reader r = proc.output);
    assert(exists result = r.readLine());

    value nums = result.split((x) => x == '.')
        .map((x) => x.trimmed)
        .take(2)
        .map(parseInteger).sequence();

    assert(exists major = nums[0],
           exists minor = nums[1]);

    "LLVM version should be = 3.x"
    assert(major == 3);

    return [major, minor];
}

"The current LLVM version"
[Integer, Integer] llvmVersion = getLLVMVersion();

"An LLVM compilation unit."
class LLVMUnit() {
    value items = ArrayList<LLVMDeclaration>();
    value declarations = HashMap<String,LLVMType>();
    value unnededDeclarations = HashSet<String>();

    shared void append(LLVMDeclaration item) {
        items.add(item);
        declarations.putAll(item.declarationsNeeded);
        unnededDeclarations.add(item.name);
    }

    value declarationCode {
        declarations.removeAll(unnededDeclarations);

        function writeDeclaration(String->LLVMType declaration) {
            value name->type = declaration;
            if (is AnyLLVMFunctionType type) {
                value ret = type.returnType else "void";
                value args = ", ".join(type.argumentTypes);
                return "declare ``ret`` @``name``(``args``)";
            } else {
                return "@``name`` = external global ``type``";
            }
        }
        return "\n".join(declarations.map(writeDeclaration));
    }

    String constructorItem {
        String? constructorString(LLVMDeclaration dec) {
            if (! is LLVMFunction dec) {
                return null;
            }

            if (! dec.isConstructor) {
                return null;
            }

            assert(exists priority = dec.constructorPriority);

            return
                "%.constructor_type { i32 ``priority``, void ()* @``dec.name`` }";
        }

        value constructors = items.map(constructorString).narrow<String>();
        return "@llvm.global_ctors = appending global \
                [``constructors.size`` x %.constructor_type] \
                [``", ".join(constructors)``]";
    }

    string => "\n\n".join({declarationCode, constructorItem, *items}
            .map(Object.string));
}

"An LLVM function declaration."
class LLVMFunction(String n, shared LLVMType? returnType,
                   shared String modifiers,
                   shared [AnyLLVMValue*] arguments)
        extends LLVMDeclaration(n) {
    "Counter for auto-naming temporary registers."
    variable value nextTemporary = 0;

    "List of declarations"
    value declarationList = HashMap<String,LLVMType>();

    "Types of the arguments"
    value argumentTypes = arguments.map((x) => x.type).sequence();

    "Public list of declarations"
    shared actual {<String->LLVMType>*} declarationsNeeded => declarationList;

    shared AnyLLVMFunctionType llvmType => FuncType(returnType, argumentTypes);

    "The argument list as a single code string."
    shared String argList => ", ".join(arguments.map(Object.string));

    "Memoization of constructorPriority."
    variable Integer? constructorPriority_ = null;

    "If set, this function will be run as a 'constructor' by the linker. The
     value is a priority that determines what order such functions are run
     in if multiple are declared."
    shared Integer? constructorPriority => constructorPriority_;

    "Is this a constructor? (In the LLVM/system linker sense)."
    shared Boolean isConstructor => constructorPriority_ exists;

    "Make this function a constructor (In the LLVM/system linker sense)."
    shared void makeConstructor(Integer priority)
        => constructorPriority_ = priority;

    "A default return statement, in case none is provided."
    value stubReturn =
        if (exists returnType)
        then "ret ``returnType`` null"
        else "ret void";

    "Counter for auto-naming labels."
    variable value nextTemporaryLabel = 0;

    "An LLVM label for this function."
    class FuncLabel() extends Label(label) {
        shared String tag = ".l``nextTemporaryLabel++``";
        identifier = "%``tag``";
    }

    "An LLVM logical block."
    class Block() {
        "The jump label at the start of this block."
        shared FuncLabel label = FuncLabel();

        "List of instructions."
        value instructions_ = ArrayList<String>();

        "Whether we've had a terminating instruction.
         Updated from outside the class."
        variable value terminated_ = false;

        "Read accessor for terminated_."
        shared Boolean terminated => terminated_;

        "Mark that we've had a terminating instruction."
        shared void terminate() {
            "Block should not be terminated twice."
            assert(!terminated);
            terminated_ = true;
        }

        "Accessor for instructions with appended default return."
        shared [String*] instructions =>
            if (terminated)
            then instructions_.sequence()
            else instructions_.sequence().withTrailing(stubReturn);

        "Add an instruction to this logical block."
        shared void instruction(String instruction) {
            "Block should not have instructions after termination."
            assert(!terminated);
            instructions_.add(instruction);
        }

        string => "``label.tag``:\n    "
            + "\n    ".join(instructions);
    }

    "The logical block we are currently adding instructions to."
    variable value currentBlock = Block();

    "Instructions in the body of this function that perform the main business
     logic."
    value blocks = ArrayList{currentBlock};

    "Label for the block we are currently adding instructions to."
    shared Label block => currentBlock.label;

    "Switch to an existing block."
    assign block {
        value candidates = blocks.select((x) => x.label == block);

        "Label should match exactly one block."
        assert(candidates.size == 1);

        assert(exists newBlock = candidates.first);

        currentBlock = newBlock;
    }

    "The entry point for the function."
    shared variable Label entryPoint = block;

    "Create a new block."
    shared Label newBlock() {
        value newBlock = Block();
        blocks.add(newBlock);
        return newBlock.label;
    }

    "Function body as a single code string."
    value body => "\n  ".join(blocks);

    shared void instruction(String instruction)
        => currentBlock.instruction(instruction);

    "Note that a declaration is required for this function."
    shared void declaration(String name, LLVMType declaration)
        => declarationList.put(name, declaration);

    string => "define ``modifiers`` ``returnType else "void"`` @``name``(``argList``) {
                   br ``entryPoint``
                 ``body``
               }";

    "Register value objects for this function."
    class Register<T>(T type, String? regNameIn)
            extends LLVMValue<T>(type)
            given T satisfies LLVMType {
        identifier =
            if (exists regNameIn)
            then "%``regNameIn``"
            else "%.``nextTemporary++``";
    }

    "Get a register for a given type"
    shared LLVMValue<T> register<T>(T type, String? regNameIn = null)
            given T satisfies LLVMType
        => Register(type, regNameIn);

    "Access a global from this function"
    shared Ptr<T> global<T>(T t, String name) given T satisfies LLVMType {
        value ret = object extends Ptr<T>(ptr(t)) {
            identifier = "@``name``";
        };
        if (name.startsWith(".str")) {
            return ret;
        }
        if (name.endsWith("$Basic$vtable")) {
            return ret;
        }
        declaration(name, t);
        return ret;
    }

    "Emit a call instruction for a function pointer"
    shared LLVMValue<R>? tailCallPtr<R>(Ptr<FuncType<R,Nothing>> func, AnyLLVMValue* args) {
        value argList = ", ".join(args);
        value retType = func.type.targetType.returnType;
        value ret = retType?.string else "void";
        value reg =
            if (exists retType)
            then register(retType)
            else null;
        value assignment =
            if (exists reg)
            then "``reg.identifier`` = "
            else "";

        instruction("``assignment``tail call ``ret`` ``func.identifier``(``argList``)");
        return reg;
    }

    "Emit a call instruction returning void"
    shared void callVoid(String name, AnyLLVMValue* args) {
        value argList = ", ".join(args);

        instruction("call void @``name``(``argList``)");
        declaration(name, FuncType(null, args.collect((x) => x.type)));
    }

    "Emit a call instruction"
    shared LLVMValue<T> call<T>(T type, String name, AnyLLVMValue* args)
            given T satisfies LLVMType {
        value argList = ", ".join(args);

        value result = register(type);

        instruction("``result.identifier`` = \
                     call ``type`` @``name``(``argList``)");
        declaration(name, FuncType(type, args.collect((x) => x.type)));

        return result;
    }

    "Add a return statement to this block"
    shared void ret<T>(LLVMValue<T>? val)
            given T satisfies LLVMType {
        if (exists val) {
            instruction("ret ``val``");
        } else {
            instruction("ret void");
        }

        currentBlock.terminate();
    }

    "Add an integer operation instruction to this block"
    I64 intOp(String op, I64|Integer a, I64|Integer b) {
        value ret = register(i64);
        instruction("``ret.identifier`` = ``op`` ``a``, ``b``");
        return ret;
    }

    "Add an add instruction to this block"
    shared I64 add(I64|Integer a, I64|Integer b) => intOp("add", a, b);

    "Add a mul instruction to this block"
    shared I64 mul(I64|Integer a, I64|Integer b) => intOp("mul", a, b);

    "Offset a pointer"
    shared Ptr<T> offset<T>(Ptr<T> ptr, I64 amount)
            given T satisfies LLVMType {
        value result = register(ptr.type);

        if (llvmVersion[1] < 7) {
            instruction("``result.identifier`` = getelementptr ``ptr``, ``amount``");
        } else {
            instruction("``result.identifier`` = getelementptr ``ptr.type.targetType``, \
                         ``ptr``, ``amount``");
        }

        return result;
    }

    "Load from a pointer"
    shared LLVMValue<T> load<T>(Ptr<T> ptr, I64? off = null)
            given T satisfies LLVMType {
        if (exists off) {
            return load(offset(ptr, off));
        }

        value result = register(ptr.type.targetType);

        if (llvmVersion[1] < 7) {
            instruction("``result.identifier`` = load ``ptr``");
        } else {
            instruction("``result.identifier`` = load ``result.type``, ``ptr``");
        }

        return result;
    }

    "Store to a pointer"
    shared void store<T>(Ptr<T> ptr, LLVMValue<T> val, I64? off = null)
            given T satisfies LLVMType {
        if (exists off) {
            store(offset(ptr, off), val);
        } else {
            instruction("store ``val``, ``ptr``");
        }
    }

    "Cast an I64 to a Ptr<I64>"
    shared Ptr<T> toPtr<T>(I64 p, T t)
            given T satisfies LLVMType {
        value result = register(ptr(t));
        instruction("``result.identifier`` = inttoptr ``p`` \
                     to ``result.type``");
        return result;
    }

    "Cast a Ptr<I64> to an I64"
    shared I64 toI64<T>(Ptr<T> ptr) given T satisfies LLVMType {
        value result = register(i64);
        instruction("``result.identifier`` = ptrtoint ``ptr`` \
                     to ``result.type``");
        return result;
    }

    "Compare two values and see if they are equal."
    shared I1 compareEq<T>(T a, T b)
            given T satisfies AnyLLVMValue {
        value result = register(i1);
        instruction("``result.identifier`` = icmp eq ``a``, ``b.identifier``");
        return result;
    }

    "Jump to the given label."
    shared void jump(Label l) {
        instruction("br ``l``");
        currentBlock.terminate();
    }

    "Branch on the given conditional"
    shared void branch(I1 condition, Label t, Label f) {
        instruction("br ``condition``, ``t``, ``f``");
        currentBlock.terminate();
    }
}

"An LLVM global variable declaration."
class LLVMGlobal<out T>(String n, LLVMValue<T> startValue, String modifiers = "")
        extends LLVMDeclaration(n)
        given T satisfies LLVMType {
    string => "@``name`` = ``modifiers`` global ``startValue``";
}

"Alias supertype of all globals"
alias AnyLLVMGlobal => LLVMGlobal<LLVMType>;
