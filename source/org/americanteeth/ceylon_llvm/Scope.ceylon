import ceylon.interop.java {
    CeylonList
}

import ceylon.collection {
    ArrayList,
    HashMap,
    HashSet
}

import com.redhat.ceylon.model.typechecker.model {
    FunctionModel = Function,
    ValueModel = Value,
    DeclarationModel = Declaration
}

"A scope containing instructions"
abstract class Scope(FunctionModel|ValueModel? model = null) {
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

    "Get the frame variable for a nested declaration"
    shared default String? getFrameFor(DeclarationModel declaration) {
        "Default getFrameFor must be overriden for top level"
        assert(exists model);

        if (allocations.defines(declaration)) {
            return "%.frame";
        }

        if (declaration.toplevel) {
            return null;
        }

        value container = declaration.container;

        if (container == model) {
            return "%.frame";
        }

        variable Anything visitedContainer = (model of DeclarationModel).container;
        variable String context = "%.context";

        while (is DeclarationModel v = visitedContainer, v != container) {
            value fetch = allocateTemporary();
            value cast = allocateTemporary();

            addInstruction("``fetch`` = load i64,i64* ``context``");
            addInstruction("``cast`` = inttoptr i64 ``fetch`` to i64*");
            context = cast;

            visitedContainer = v.container;
        }

        "We should always find a parent scope. We'll get to a 'Package' if we
         don't"
        assert(container is DeclarationModel);

        return context;
    }

    "Add instructions to fetch an allocated element"
    shared default GetterScope getterFor(ValueModel model) {
        assert(exists offset = allocations[model]);
        value getterScope = GetterScope(model);
        value address = getterScope.allocateTemporary();
        value data = getterScope.allocateTemporary();
        value cast = getterScope.allocateTemporary();

        getterScope.addInstruction("``address`` = getelementptr i64, \
                                    i64* %.context, i32 ``offset + 1``");
        getterScope.addInstruction("``data`` = load i64,i64* ``address``");
        getterScope.addInstruction("``cast`` = inttoptr i64 ``data`` to i64*");
        getterScope.addInstruction("ret i64* ``cast``");

        return getterScope;
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
                value offset = allocateTemporary();
                addInstruction("``tmp`` = ptrtoint i64* \
                                ``startValue`` to i64");

                /* allocationBlock = the new allocation position + 1 */
                addInstruction("``offset`` = getelementptr i64, i64* %.frame, \
                                i32 ``allocationBlock``");
                addInstruction("store i64 ``tmp``, i64* ``offset``");
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

    "Access a declaration"
    shared String access(ValueModel declaration) {
        if (exists cached = currentValues[declaration]) {
            return cached;
        }

        usedItems.add(declaration);

        value context = if (exists f = getFrameFor(declaration))
                        then "i64* ``f``"
                        else "";

        value ret = allocateTemporary();
        addInstruction( "``ret`` = call i64* \
                         @``declarationName(declaration)``$get(``context``)");
        return ret;
    }

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

        value nestedScope = if (is ValueModel model) then !model.toplevel
        else if (is FunctionModel model) then !model.toplevel else false;

        if (nestedScope) {
            result.append("i64* %.context");

            if (! arguments.empty) {
                result.append(", ");
            }
        }

        result.append(arguments);
        result.append(") {\n");

        if (allocationBlock > 0 || nestedScope) {
            value blocksTotal =
                if (nestedScope)
                then allocationBlock + 1
                else allocationBlock;
            value bytesTotal = blocksTotal * 8;

            result.append("    %.frame = call i64* \
                           @malloc(i64 ``bytesTotal``)\n");

            if (nestedScope) {
                result.append("    %.context_cast = \
                               ptrtoint i64* %.context to i64\n");
                result.append("    store i64 %.context_cast, i64* %.frame\n");
            }

            result.append("\n");
        } else {
            result.append("    %.frame = bitcast i64* null to i64*\n\n");
        }

        for (instruction in instructions) {
            result.append("    ``instruction``\n");
        }

        result.append(postfix);
        result.append("}\n\n");

        return result.string;
    }
}

"Scope of a getter method"
class GetterScope(ValueModel model) extends Scope(model) {
    shared actual String definitionName => declarationName(model) + "$get";
}

"Scope of a setter method"
class SetterScope(ValueModel model) extends Scope(model) {
    shared actual String definitionName => declarationName(model) + "$set";
}

"The scope of a function"
class FunctionScope(FunctionModel model) extends Scope(model) {
    shared actual String definitionName => declarationName(model);
    shared actual String postfix => "    ret i64* null\n";
    shared actual String arguments {
        value result = StringBuilder();
        variable Boolean first = true;

        for(item in CeylonList(model.firstParameterList.parameters)) {
            if (! first) {
                result.append(", ");
            }

            first = false;
            result.append("i64* %``item.name``");
        }

        return result.string;
    }
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

    shared actual String? getFrameFor(DeclarationModel declaration) => null;
}

