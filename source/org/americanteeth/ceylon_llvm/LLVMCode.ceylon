import ceylon.collection { ArrayList }

abstract class LLVMDeclaration(shared String name) {}

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
        shared [String*] arguments,
        shared [String*] bodyStart) extends LLVMDeclaration(n) {

    String argList => ", ".join(arguments);
    String modString => if (modifiers.empty) then "" else modifiers + " ";

    variable Integer? constructorPriority_ = null;
    shared Integer? constructorPriority => constructorPriority_;
    shared Boolean isConstructor => constructorPriority_ exists;
    shared void makeConstructor(Integer priority)
        => constructorPriority_ = priority;

    value bodyItems = ArrayList{*bodyStart};
    value body => "\n    ".join(bodyItems);

    value bodyPadded => if (body.empty) then "" else "\n    ``body``\n";

    shared void addInstructions(String* instructions)
        => bodyItems.addAll(instructions);

    string => "define ``modString````returnType`` @``name``(``argList``) {\
               ``bodyPadded``}";
}

class LLVMGlobal(String n, String? startValue = null)
        extends LLVMDeclaration(n) {
    string => "@``name`` = global i64* ``startValue else "null"``";
}
