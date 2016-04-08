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

"Something to which an instruction may be added. Usually a function body, or a
 register (in which case the instruction says how to assign that register)."
interface LLVMCodeTarget<ReturnValue> {
    shared formal ReturnValue instruction(String instruction);
    shared default String resultType => "void";

    shared ReturnValue call(String name, String* args) {
        value argList = ", ".join(args.map((x) => "i64* ``x``"));

        return instruction("call ``resultType`` @``name``(``argList``)");
    }
}

"An LLVM Register. Adding an instruction to it will assign that register the
 result of that instruction."
interface LLVMRegister satisfies LLVMCodeTarget<String> {
    shared String load(String from, String? index = null)
        => if (llvmVersion[1] < 7)
           then instruction("load ``resultType``* ``from``")
           else instruction("load ``resultType``,``resultType``* ``from``");
    shared String offsetPointer(String register, String offset)
        => if (llvmVersion[1] < 7)
           then instruction("getelementptr \
                             ``resultType`` ``register``, i64 ``offset``")
           else instruction("getelementptr ``unPointer(resultType)``, \
                             ``resultType`` ``register``, i64 ``offset``");
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
        satisfies LLVMCodeTarget<Anything> {
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
        else mainBodyItems.sequence().withTrailing(stubReturn);

    "Function body as a single code string."
    value body => "\n    ".join(bodyItems);

    "A block of instructions that precedes the main body and can be used to set
     up a context."
    shared object preamble satisfies LLVMCodeTarget<Anything> {
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

    "Get a new register to which you may assign a value."
    LLVMRegister anyRegister(String resultTypeIn, String? regNameIn)
        => object satisfies LLVMRegister {
            shared actual String resultType = resultTypeIn;

            value regName =
                if (exists regNameIn)
                then "%.``regNameIn``"
                else "%.``nextTemporary++``";

            shared actual String instruction(String instruction) {
                mainBodyItems.add("``regName`` = ``instruction``");
                return regName;
            }

            string => regName;
        };

    "Get a new i64* register"
    shared LLVMRegister register(String? name = null)
        => anyRegister("i64*", name);

    "Get a new i64 register"
    shared LLVMRegister registerInt(String? name = null)
        => anyRegister("i64", name);

    "Add a return statement to this function"
    shared void ret(String? val) {
        if (exists val) {
            instruction("ret ``returnType`` ``val``");
        } else {
            assert(returnType == "void");
            instruction("ret void");
        }
    }
}

"An LLVM global variable declaration."
class LLVMGlobal(String n, String? startValue = null)
        extends LLVMDeclaration(n) {
    string => "@``name`` = global i64* ``startValue else "null"``";
}
