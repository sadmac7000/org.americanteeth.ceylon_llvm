import ceylon.collection { ArrayList }
import ceylon.process {
    createProcess,
    currentError
}

import ceylon.file {
    Reader
}

"Any top-level declaration in an LLVM compilation unit."
abstract class LLVMDeclaration(shared String name) {}

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

    "Emit a call instruction"
    shared T call<T=Anything>(String name, LLVMValue* args) {
        value argList = ", ".join(args);

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

        assert(is T result);
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
    shared default Ptr<T> offset(I64 amount) { assert(false); }
    shared default T fetch(I64? off=null) { assert(false); }
    shared actual default String typeName => "i64*";
    shared formal I64 i64();
}


"An LLVM 64-bit integer value"
interface I64 satisfies LLVMValue {
    typeName => "i64";
    shared formal Ptr<I64> i64p();
}

"A literal LLVM I64"
final class I64Lit(Integer val) satisfies I64 {
    identifier = val.string;
    shared actual Ptr<I64> i64p() { assert(false); }
}

"An LLVM Null value"
object llvmNull satisfies Ptr<I64> {
    identifier = "null";
    shared actual I64 i64() => I64Lit(0);
}

"An LLVM compilation unit."
class LLVMUnit() {
    value items = ArrayList<LLVMDeclaration>();

    shared void append(LLVMDeclaration item) => items.add(item);

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

    string => "\n\n".join(items.map(Object.string).follow(constructorItem));
}

"An LLVM function declaration."
class LLVMFunction(String n, shared String returnType,
                   shared String modifiers,
                   shared [String*] arguments)
        extends LLVMDeclaration(n)
        satisfies LLVMBlock {
    "Counter for auto-naming temporary registers."
    variable value nextTemporary = 0;

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

    "Instructions in the body of this function. This is a separate block of
     instructions that runs before the 'main' instructions."
    value preambleItems = ArrayList<String>();

    "All instructions in the body of this function."
    value bodyItems =>
        if (exists b = mainBodyItems.last, b.startsWith("ret "))
        then preambleItems.chain(mainBodyItems)
        else preambleItems.chain(mainBodyItems).sequence().withTrailing(stubReturn);

    "Function body as a single code string."
    value body => "\n    ".join(bodyItems);

    "A block of instructions that precedes the main body and can be used to set
     up a context."
    shared object preamble satisfies LLVMBlock {
        shared actual <T&LLVMValue>? registerFor<T>(String? regNameIn)
            => outer.registerFor(regNameIn);
        shared actual void instruction(String instruction)
            => preambleItems.add(instruction);
    }

    shared void addInstructions(String* instructions)
        => mainBodyItems.addAll(instructions);

    shared actual void instruction(String instruction)
        => mainBodyItems.add(instruction);

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

        shared actual T fetch(I64? off) {
            if (exists off) {
                return offset(off).fetch();
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

        shared actual String typeName => writeReg().typeName + "*";
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
    shared Ptr<T> global<T>(String name) given T satisfies LLVMValue
        => object satisfies PointerImpl<T> {
            identifier = "@``name``";
        };

    "Add a return statement to this function"
    shared void ret(LLVMValue? val) {
        if (exists val) {
            instruction("ret ``val``");
        } else {
            assert(returnType == "void");
            instruction("ret void");
        }
    }

    "Add an add instruction to this function"
    shared I64 add(I64|Integer a, I64|Integer b) {
        value ret = registerInt();
        instruction("``ret.identifier`` = add ``a``, ``b``");
        return ret;
    }
}

"An LLVM global variable declaration."
class LLVMGlobal(String n, LLVMValue startValue = llvmNull)
        extends LLVMDeclaration(n) {
    string => "@``name`` = global ``startValue``";
}
