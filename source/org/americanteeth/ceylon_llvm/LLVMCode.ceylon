import ceylon.collection { ArrayList }

"Any top-level declaration in an LLVM compilation unit."
abstract class LLVMDeclaration(shared String name) {}

"Something to which an instruction may be added. Usually a function body, or a
register (in which case the instruction says how to assign that register)."
interface LLVMCodeTarget<ReturnValue> {
    shared formal ReturnValue instruction(String instruction);
    shared default String resultType => "void";

    shared void ret(String val) => instruction("ret i64* ``val``");

    shared ReturnValue call(String name, String* args) {
        value argList = ", ".join(args.map((x) => "i64* ``x``"));

        return instruction("call ``resultType`` @``name``(``argList``)");
    }
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
    shared LLVMCodeTarget<String> register(String? regNameIn = null)
        => object satisfies LLVMCodeTarget<String> {
            shared actual String resultType = "i64*";

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
}

"An LLVM global variable declaration."
class LLVMGlobal(String n, String? startValue = null)
        extends LLVMDeclaration(n) {
    string => "@``name`` = global i64* ``startValue else "null"``";
}
