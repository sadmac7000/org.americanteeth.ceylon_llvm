import ceylon.collection { ArrayList }

abstract class LLVMDeclaration() {}

class LLVMUnit() {
    value items = ArrayList<String|LLVMDeclaration>();

    shared void append(String|LLVMDeclaration item) => items.add(item);

    string => "\n\n".join(items.map(Object.string));
}

class LLVMFunction(shared String name, shared String returnType,
        shared String modifiers,
        shared [String*] arguments,
        shared [String*] bodyStart) extends LLVMDeclaration() {

    String argList => ", ".join(arguments);
    String modString => if (modifiers.empty) then "" else modifiers + " ";

    value bodyItems = ArrayList{*bodyStart};
    value body => "\n    ".join(bodyItems);

    value bodyPadded => if (body.empty) then "" else "\n    ``body``\n";

    shared void addInstructions(String* instructions)
        => bodyItems.addAll(instructions);

    string => "define ``modString````returnType`` @``name``(``argList``) {\
               ``bodyPadded``}";
}
