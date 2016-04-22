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

"Get the dereference of an LLVM pointer type"
String unPointer(String type) {
    assert(type.endsWith("*"));
    return type.spanTo(type.size - 2);
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
}

"An LLVM typed value"
interface LLVMValue {
    shared formal String identifier;
    shared formal String typeName;
    string => "``typeName`` ``identifier``";
}

"An LLVM pointer value"
interface Ptr<T> satisfies LLVMValue given T satisfies LLVMValue {
    shared default Ptr<T> offset(I64 amount) { assert(false); }
    shared default T load(I64? off=null) { assert(false); }
    shared actual default String typeName => "i64*";
    shared formal I64 i64();
    shared formal void store(T val, I64? off=null);
}


"An LLVM 64-bit integer value"
interface I64 satisfies LLVMValue {
    typeName => "i64";
    shared formal Ptr<I64> i64p();
}

"A literal LLVM i64"
final class I64Lit(Integer val) satisfies I64 {
    identifier = val.string;
    shared actual Ptr<I64> i64p() { assert(false); }
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
    shared actual I64 i64() => I64Lit(0);
    shared actual void store(I64 val, I64? off) {
        "Cannot store to null pointer."
        assert(false);
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

    "Public list of declarations"
    shared actual {String*} declarationsNeeded => declarationList;

    "The declaration that we don't need because we have this definition"
    shared actual String declarationMade {
        value types =
            arguments.map((x) => x.split()).map((x) => x.first).narrow<String>();
        value typeList = ", ".join(types);
        return "declare ``returnType`` @``n``(``typeList``)";
    }

    "The argument list as a single code string."
    String argList => ", ".join(arguments);

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
        Ptr<T> offsetReg() {
            assert(exists ret = registerFor<Ptr<T>>());
            return ret;
        }

        T writeReg() {
            assert(exists ret = registerFor<T>());
            return ret;
        }

        shared actual Ptr<T> offset(I64 amount) {
            value result = offsetReg();
            value dummy = writeReg(); // If you think this hack is bad you
                                      // should see the other things I tried.

            if (llvmVersion[1] < 7) {
                instruction("``result.identifier`` = getelementptr ``this``, ``amount``");
            } else {
                instruction("``result.identifier`` = getelementptr ``dummy.typeName``, \
                             ``this``, ``amount``");
            }

            return result;
        }

        shared actual T load(I64? off) {
            if (exists off) {
                return offset(off).load();
            }

            value result = writeReg();

            if (llvmVersion[1] < 7) {
                instruction("``result.identifier`` = load ``this``");
            } else {
                instruction("``result.identifier`` = load ``result.typeName``, ``this``");
            }

            return result;
        }

        shared actual I64 i64() {
            value result = registerInt();

            instruction("``result.identifier`` = ptrtoint ``this`` to i64");
            return result;
        }

        shared actual void store(T val, I64? off) {
            if (exists off) {
                offset(off).store(val);
            } else {
                instruction("store ``val``, ``this``");
            }
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
            shared actual Ptr<I64> i64p() {
                value result = register();
                instruction("``result.identifier`` = inttoptr ``this`` \
                             to ``result.typeName``");
                return result;
            }
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
class LLVMGlobal(String n, LLVMValue startValue = llvmNull)
        extends LLVMDeclaration(n) {
    string => "@``name`` = global ``startValue``";
    declarationMade => "@``name`` = external global ``startValue.typeName``";
}
