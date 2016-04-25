import ceylon.collection {
    ArrayList,
    HashSet
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
    shared default {String*} declarationsNeeded = {};
    shared default String? declarationMade = null;
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

"A sequence of LLVM instructions"
interface LLVMBlock {
    shared formal void instruction(String instruction);
    shared formal LLVMValue<T> registerFor<T>(T type, String? regNameIn = null)
            given T satisfies LLVMType;
    shared default void declaration(String declaration) {}

    shared void callVoid(String name, AnyLLVMValue* args) {
        value argList = ", ".join(args);
        value typeList = ", ".join(args.map((x) => x.typeName));

        instruction("call void @``name``(``argList``)");
        declaration("declare void @``name``(``typeList``)");
    }

    "Emit a call instruction"
    shared LLVMValue<T> call<T>(T type, String name, AnyLLVMValue* args)
            given T satisfies LLVMType {
        value argList = ", ".join(args);
        value typeList = ", ".join(args.map((x) => x.typeName));

        value result = registerFor(type);

        instruction("``result.identifier`` = \
                     call ``type`` @``name``(``argList``)");
        declaration("declare ``type`` @``name``(``typeList``)");

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
    }

    "Add an integer operation instruction to this block"
    I64 intOp(String op, I64|Integer a, I64|Integer b) {
        value ret = registerFor(i64);
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
        value result = registerFor(ptr.type);

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

        value result = registerFor(ptr.type.targetType);

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
    shared Ptr<I64Type> toPtr(I64 p) {
        value result = registerFor(ptr(i64));
        instruction("``result.identifier`` = inttoptr ``p`` \
                     to ``result.type``");
        return result;
    }

    "Cast a Ptr<I64> to an I64"
    shared I64 toI64(Ptr<I64Type> ptr) {
        value result = registerFor(i64);
        instruction("``result.identifier`` = ptrtoint ``ptr`` \
                     to ``result.type``");
        return result;
    }
}

"An LLVM compilation unit."
class LLVMUnit() {
    value items = ArrayList<LLVMDeclaration>();
    value declarations = HashSet<String>();
    value unnededDeclarations = HashSet<String>();

    shared void append(LLVMDeclaration item) {
        items.add(item);
        declarations.addAll(item.declarationsNeeded);
        if (exists i = item.declarationMade) {
            unnededDeclarations.add(i);
        }
    }

    value declarationCode {
        declarations.removeAll(unnededDeclarations);
        return "\n".join(declarations);
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
                   shared [String*] arguments)
        extends LLVMDeclaration(n)
        satisfies LLVMBlock {
    "Counter for auto-naming temporary registers."
    variable value nextTemporary = 0;

    "Position where we will insert instructions"
    variable value insertPos = 0;

    "List of declarations"
    value declarationList = ArrayList<String>();

    "Types of the arguments"
    value argumentTypes =
        arguments.map((x) => x.split()).map((x) => x.first).narrow<String>();

    "LLVM list of the types of the arguments"
    value typeList = ", ".join(argumentTypes);

    "Public list of declarations"
    shared actual {String*} declarationsNeeded => declarationList;

    "The declaration that we don't need because we have this definition"
    shared actual String declarationMade
        => "declare ``returnType else "void"`` @``n``(``typeList``)";

    shared String llvmType => "``returnType else "void"``(``typeList``)";

    "The argument list as a single code string."
    shared String argList => ", ".join(arguments);

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

    "Instructions in the body of this function that perform the main business
     logic."
    value mainBodyItems = ArrayList<String>();

    "All instructions in the body of this function."
    value bodyItems =>
        if (exists b = mainBodyItems.last, b.startsWith("ret "))
        then mainBodyItems
        else mainBodyItems.sequence().withTrailing(stubReturn);

    "Function body as a single code string."
    value body => "\n    ".join(bodyItems);

    shared actual void instruction(String instruction)
        => mainBodyItems.insert(insertPos++, instruction);

    "Set the index in the instruction list where we will add instructions"
    shared void setInsertPosition(Integer? pos = null) {
        if (exists pos) {
            insertPos = pos;
        } else {
            insertPos = mainBodyItems.size;
        }
    }

    shared actual void declaration(String declaration)
        => declarationList.add(declaration);

    string => "define ``modifiers`` ``returnType else "void"`` @``name``(``argList``) {
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
    shared actual LLVMValue<T> registerFor<T>(T type, String? regNameIn)
            given T satisfies LLVMType
        => Register(type, regNameIn);

    "Get a new i64* register"
    shared Ptr<I64Type> register(String? regNameIn = null)
        => registerFor(ptr(i64), regNameIn);

    "Get a new i64 register"
    shared I64 registerInt(String? regNameIn = null)
        => registerFor(i64, regNameIn);

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
        declaration("``ret.identifier`` = external global ``t``");
        return ret;
    }
}

"An LLVM global variable declaration."
class LLVMGlobal<out T>(String n, LLVMValue<T> startValue, String modifiers = "")
        extends LLVMDeclaration(n)
        given T satisfies LLVMType {
    string => "@``name`` = ``modifiers`` global ``startValue``";
    declarationMade => "@``name`` = external global ``startValue.type``";
}

"Alias supertype of all globals"
alias AnyLLVMGlobal => LLVMGlobal<LLVMType>;
