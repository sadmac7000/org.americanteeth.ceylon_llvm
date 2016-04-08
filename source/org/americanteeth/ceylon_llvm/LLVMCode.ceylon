import ceylon.collection { ArrayList }

abstract class LLVMDeclaration(shared String name) {}

interface LLVMCodeTarget<ReturnValue>
        given ReturnValue satisfies Anything {
    shared formal ReturnValue instruction(String instruction);
    shared default String resultType => "void";

    shared void ret(String val) => instruction("ret i64* ``val``");

    shared ReturnValue call(String name, String* args) {
        value argList = ", ".join(args.map((x) => "i64* ``x``"));

        return instruction("call ``resultType`` @``name``(``argList``)");
    }
}

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

class LLVMFunction(String n, shared String returnType,
                   shared String modifiers,
                   shared [String*] arguments)
        extends LLVMDeclaration(n)
        satisfies LLVMCodeTarget<Anything> {
    variable value nextTemporary = 0;

    String argList => ", ".join(arguments);

    variable Integer? constructorPriority_ = null;
    shared Integer? constructorPriority => constructorPriority_;
    shared Boolean isConstructor => constructorPriority_ exists;
    shared void makeConstructor(Integer priority)
        => constructorPriority_ = priority;

    value stubReturn = switch(returnType)
        case ("i64*") "ret i64* null"
        case ("void") "ret void"
        else "/* Could not generate default return */";

    value mainBodyItems = ArrayList<String>();
    value preambleItems = ArrayList<String>();

    value bodyItems =>
        if (exists b = mainBodyItems.last, b.startsWith("ret "))
        then preambleItems.chain(mainBodyItems)
        else mainBodyItems.sequence().withTrailing(stubReturn);

    value body => "\n    ".join(bodyItems);

    value bodyPadded => if (body.empty) then "" else "\n    ``body``\n";

    shared object preamble satisfies LLVMCodeTarget<Anything> {
        shared actual void instruction(String instruction)
            => preambleItems.add(instruction);
    }

    shared void addInstructions(String* instructions)
        => mainBodyItems.addAll(instructions);
    shared actual void instruction(String instruction)
        => mainBodyItems.add(instruction);

    string => "define ``modifiers`` ``returnType`` @``name``(``argList``) {\
               ``bodyPadded``}";

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

class LLVMGlobal(String n, String? startValue = null)
        extends LLVMDeclaration(n) {
    string => "@``name`` = global i64* ``startValue else "null"``";
}
