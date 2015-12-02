import ceylon.ast.core {
    ...
}

import ceylon.collection {
    ArrayList,
    HashMap,
    HashSet
}

import com.redhat.ceylon.model.typechecker.model {
    FunctionModel = Function,
    ValueModel = Value
}

"A scope containing instructions"
abstract class Scope() {
    value currentValues = HashMap<ValueModel,String>();
    value allocations = HashMap<ValueModel,Integer>();
    variable value allocationBlock = 0;
    variable value nextTemporary = 0;

    shared HashSet<ValueModel> usedItems = HashSet<ValueModel>();

    value instructions = ArrayList<String>();

    "Allocate a new temporary label"
    shared String allocateTemporary() => "%.``nextTemporary++``";

    "Add an instruction to this scope"
    shared void addInstruction(String instruction)
        => instructions.add(instruction);

    "Whether any instructions have been added"
    shared Boolean hasInstructions => !instructions.empty;

    "Access a declaration"
    shared String access(ValueModel declaration) {
        if (exists cached = currentValues[declaration]) {
            return cached;
        }

        usedItems.add(declaration);
        value ret = allocateTemporary();
        addInstruction( "``ret`` = call i64* \
                         @``declarationName(declaration)``$get()");
        return ret;
    }

    "Add instructions to fetch an allocated element"
    shared default GetterScope getterFor(ValueModel model) {
        return GetterScope(model);
    }

    "Add instructions to write an allocated element"
    shared default SetterScope setterFor(ValueModel model) {
        return SetterScope(model);
    }

    "Create space in this scope for a value"
    shared default void allocate(ValueModel declaration,
            String? startValue) {
        if (declaration.captured || declaration.\ishared) {
            allocations.put(declaration, allocationBlock++);
            if (exists startValue) {
                value tmp = allocateTemporary();
                addInstruction("``tmp`` = bitcast i64* \
                                ``startValue`` to i64");
                addInstruction("store i64 ``tmp``, i64* ");
            }
        } else if (exists startValue) {
            currentValues.put(declaration, startValue);
        }
    }

    "Name of the function definition we will generate"
    shared formal String definitionName;

    "Name of the function definition we will generate"
    shared default String arguments = "";
    
    "Trailing instructions for definition"
    shared default String postfix = "";

    "Visibility and linkage for the definition"
    shared default String modifiers = "";

    "LLVM return type"
    shared default String returnType = "i64*";

    shared actual default String string {
        value result = StringBuilder();
        result.append("define ");

        value mods = modifiers;

        result.append(mods);

        if (!mods.empty) {
            result.append(" ");
        }

        result.append(returnType);
        result.append(" @");
        result.append(definitionName);
        result.append("(");
        result.append(arguments);
        result.append(") {\n");

        for (instruction in instructions) {
            result.append("    ``instruction``\n");
        }

        result.append(postfix);
        result.append("}\n\n");

        return result.string;
    }
}

"Scope of a getter method"
class GetterScope(ValueModel model) extends Scope() {
    shared actual String definitionName => declarationName(model) + "$get";
}

"Scope of a setter method"
class SetterScope(ValueModel model) extends Scope() {
    shared actual String definitionName => declarationName(model) + "$set";
}

"The scope of a function"
class FunctionScope(FunctionModel model) extends Scope() {
    shared actual String definitionName => declarationName(model);
    shared actual String postfix => "    ret i64* null\n";
}

"The outermost scope of the compilation unit"
class UnitScope() extends Scope() {
    value globalVariables = StringBuilder();
    shared actual String definitionName => "__ceylon_constructor";
    shared actual String modifiers => "private";
    shared actual String returnType => "void";

    shared actual void allocate(ValueModel declaration,
            String? startValue) {
        value name = namePrefix(declaration);

        globalVariables.append(
                "@``name`` = global i64* ``startValue else "null"``\n");
    }

    "Code to register the constructor with LLVM"
    String constructor {
        if (! hasInstructions) {
            return "";
        }

        value result = StringBuilder();
        result.append("\n");
        result.append(super.string);
        result.append("%.constructor_type = type { i32, void ()*, i8* }
                       @llvm.global_ctors = appending global \
                       [1 x %.constructor_type] \
                       [%.constructor_type { i32 65535, \
                       void ()* @__ceylon_constructor, null }]\n");
        return result.string;
    }

    shared actual String string
        => globalVariables.string + constructor;

    shared actual GetterScope getterFor(ValueModel model) {
        value getterScope = GetterScope(model);
        value temp = getterScope.allocateTemporary();
        getterScope.addInstruction("``temp`` = load i64*,i64** \
                                    @``declarationName(model)``");
        getterScope.addInstruction("ret i64* ``temp``");
        return getterScope;
    }
}

