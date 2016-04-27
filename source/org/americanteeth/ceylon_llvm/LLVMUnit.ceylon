import ceylon.collection {
    ArrayList,
    HashSet,
    HashMap
}

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
            if (!is LLVMFunction dec) {
                return null;
            }

            if (!dec.isConstructor) {
                return null;
            }

            assert (exists priority = dec.constructorPriority);

            return
                "%.constructor_type { i32 ``priority``, void ()* @``dec.name
                `` }";
        }

        value constructors = items.map(constructorString).narrow<String>();
        return "@llvm.global_ctors = appending global \
                [``constructors.size`` x %.constructor_type] \
                [``", ".join(constructors)``]";
    }

    string => "\n\n".join({ declarationCode, constructorItem, *items }
            .map(Object.string));
}
