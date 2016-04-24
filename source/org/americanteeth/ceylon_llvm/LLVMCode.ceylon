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
    shared formal <T&LLVMValue>? registerFor<T>(String? regNameIn = null);
    shared default void declaration(String declaration) {}

    "Emit a call instruction"
    shared T call<T=Anything>(String name, LLVMValue* args) {
        value argList = ", ".join(args);
        value typeList = ", ".join(args.map((x) => x.typeName));

        String resultType;
        String equality;
        value result = registerFor<T>();

        if (exists result) {
            resultType = result.typeName;
            equality = "``result.identifier`` = ";
        } else {
            resultType = "void";
            equality = "";
        }

        instruction("``equality``call ``resultType`` @``name``(``argList``)");
        declaration("declare ``resultType`` @``name``(``typeList``)");

        assert(is T result);
        return result;
    }

    "Add a return statement to this block"
    shared void ret(LLVMValue? val) {
        if (exists val) {
            instruction("ret ``val``");
        } else {
            instruction("ret void");
        }
    }

    "Add an integer operation instruction to this block"
    I64 intOp(String op, I64|Integer a, I64|Integer b) {
        assert(exists ret = registerFor<I64>());
        instruction("``ret.identifier`` = ``op`` ``a``, ``b``");
        return ret;
    }

    "Add an add instruction to this block"
    shared I64 add(I64|Integer a, I64|Integer b) => intOp("add", a, b);

    "Add a mul instruction to this block"
    shared I64 mul(I64|Integer a, I64|Integer b) => intOp("mul", a, b);

    "Offset a pointer"
    shared Ptr<T> offset<T>(Ptr<T> ptr, I64 amount) {
        assert(exists result = registerFor<Ptr<T>>());
        assert(exists dummy = registerFor<T>());

        if (llvmVersion[1] < 7) {
            instruction("``result.identifier`` = getelementptr ``ptr``, ``amount``");
        } else {
            instruction("``result.identifier`` = getelementptr ``dummy.typeName``, \
                         ``ptr``, ``amount``");
        }

        return result;
    }

    "Load from a pointer"
    shared T load<T>(Ptr<T> ptr, I64? off = null) {
        if (exists off) {
            return load(offset(ptr, off));
        }

        assert(exists result = registerFor<T>());

        if (llvmVersion[1] < 7) {
            instruction("``result.identifier`` = load ``ptr``");
        } else {
            instruction("``result.identifier`` = load ``result.typeName``, ``ptr``");
        }

        return result;
    }

    "Store to a pointer"
    shared void store<T>(Ptr<T> ptr, T val, I64? off = null)
            given T satisfies LLVMValue {
        if (exists off) {
            store(offset(ptr, off), val);
        } else {
            instruction("store ``val``, ``ptr``");
        }
    }

    "Cast an I64 to a Ptr<I64>"
    shared Ptr<I64> toPtr(I64 ptr) {
        assert(exists result = registerFor<Ptr<I64>>());
        instruction("``result.identifier`` = inttoptr ``ptr`` \
                     to ``result.typeName``");
        return result;
    }

    "Cast a Ptr<I64> to an I64"
    shared I64 toI64(Ptr<I64> ptr) {
        assert(exists result = registerFor<I64>());
        instruction("``result.identifier`` = ptrtoint ``ptr`` \
                     to ``result.typeName``");
        return result;
    }
}

"An LLVM typed value"
interface LLVMValue {
    shared formal String identifier;
    shared formal String typeName;
    string => "``typeName`` ``identifier``";
}

"An LLVM pointer value"
interface Ptr<T> satisfies LLVMValue given T satisfies LLVMValue {
    shared actual default String typeName => "i64*";
}


"An LLVM 64-bit integer value"
interface I64 satisfies LLVMValue {
    typeName => "i64";
}

"A literal LLVM i64"
final class I64Lit(Integer val) satisfies I64 {
    identifier = val.string;
}

"An LLVM 32-bit integer value"
interface I32 satisfies LLVMValue {
    typeName => "i32";
}

"A literal LLVM i32"
final class I32Lit(Integer val) satisfies I32 {
    identifier = val.string;
}

"An LLVM 1-bit integer value"
interface I1 satisfies LLVMValue {
    typeName => "i1";
}

"A literal LLVM i1"
final class I1Lit(Integer val) satisfies I1 {
    identifier = val.string;
}

"An LLVM Null value"
object llvmNull satisfies Ptr<I64> {
    identifier = "null";
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
class LLVMFunction(String n, shared String returnType,
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
        => "declare ``returnType`` @``n``(``typeList``)";

    shared String llvmType => "``returnType``(``typeList``)";

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
    value stubReturn = switch(returnType)
        case ("i64*") "ret i64* null"
        case ("void") "ret void"
        else "/* Could not generate default return */";

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

    string => "define ``modifiers`` ``returnType`` @``name``(``argList``) {
                   ``body``
               }";

    "Register value objects for this function."
    abstract class Register(String? regNameIn) satisfies LLVMValue {
        identifier =
            if (exists regNameIn)
            then "%``regNameIn``"
            else "%.``nextTemporary++``";
    }

    "Get a register for a given type"
    shared actual <T&LLVMValue>? registerFor<T>(String? regNameIn) {
        value ret = {register, registerInt}.narrow<T(String?)>();

        if (ret.size > 1) {
            return null;
        } else if (exists r = ret.first) {
            return r(regNameIn);
        } else {
            return null;
        }
    }

    "Implementation for pointers"
    interface PointerImpl<T> satisfies Ptr<T> given T satisfies LLVMValue {
        T writeReg() {
            assert(exists ret = registerFor<T>());
            return ret;
        }

        shared String targetTypeName => writeReg().typeName;
        shared actual String typeName => targetTypeName + "*";
    }

    "Get a new i64* register"
    shared Ptr<I64> register(String? regNameIn = null)
        => object extends Register(regNameIn) satisfies PointerImpl<I64> {};

    "Get a new i64 register"
    shared I64 registerInt(String? regNameIn = null)
        => object extends Register(regNameIn) satisfies I64 {
        };

    "Access a global from this function"
    shared Ptr<T> global<T>(String name) given T satisfies LLVMValue {
        value ret = object satisfies PointerImpl<T> {
            identifier = "@``name``";
        };
        if (name.startsWith(".str")) {
            return ret;
        }
        if (name.endsWith("$Basic$vtable")) {
            return ret;
        }
        declaration("``ret.identifier`` = external global ``ret.targetTypeName``");
        return ret;
    }
}

"An LLVM global variable declaration."
class LLVMGlobal(String n, LLVMValue startValue = llvmNull, String modifiers = "")
        extends LLVMDeclaration(n) {
    string => "@``name`` = ``modifiers`` global ``startValue``";
    declarationMade => "@``name`` = external global ``startValue.typeName``";
}
