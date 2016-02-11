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
    ClassModel = Class,
    DeclarationModel = Declaration,
    ParameterList
}

"Priority of the library constructor function that contains all of the toplevel
 code"
Integer toplevelConstructorPriority = 65535;

"Priority of the library constructor functions that initialize vtables"
Integer vtableConstructorPriority = 65534;

"Convert a parameter list to an LLVM string"
String parameterListToLLVMString(ParameterList parameterList) {
    value result = StringBuilder();
    variable Boolean first = true;

    for(item in CeylonList(parameterList.parameters)) {
        if (! first) {
            result.append(", ");
        }

        first = false;
        result.append("i64* %``item.name``");
    }

    return result.string;
}

"Add a new definition start to a StringBuilder"
void beginDefinition(StringBuilder result, String modifiers, String returnType,
    String definitionName) {
        result.append("define ");

        result.append(modifiers);

        if (!modifiers.empty) {
            result.append(" ");
        }

        result.append(returnType);
        result.append(" @");
        result.append(definitionName);
}

"A scope containing instructions"
abstract class Scope() of CallableScope|UnitScope {
    value currentValues = HashMap<ValueModel,String>();
    value allocations = HashMap<ValueModel,Integer>();
    variable value allocationBlock = 0;
    variable value nextTemporary = 0;

    shared Integer allocatedBlocks => allocationBlock;

    shared HashSet<ValueModel> usedItems = HashSet<ValueModel>();

    "List of instructions"
    value instructions = ArrayList<String>();

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

    "Whether this scope is a nested function/class/etc."
    shared default Boolean nestedScope = false;

    "Is there an allocation for this value in the frame for this scope"
    shared Boolean allocates(ValueModel v) => allocations.defines(v);

    "Allocate a new temporary label"
    shared String allocateTemporary() => "%.``nextTemporary++``";

    "Add an instruction to this scope"
    shared void addInstruction(String instruction)
        => instructions.add(instruction);

    "Add an instruction that returns a value to this scope"
    shared String addValueInstruction(String instruction) {
        value temp = allocateTemporary();
        addInstruction("``temp`` = ``instruction``");
        return temp;
    }

    "Whether any instructions have been added"
    shared Boolean hasInstructions => !instructions.empty;

    "Get the frame variable for a nested declaration"
    shared default String? getFrameFor(DeclarationModel declaration) => null;

    "The allocation offset for this item"
    shared default String getAllocationOffset(Integer slot, Scope scope) {
        return (slot + 1).string;
    }

    "Add instructions to fetch an allocated element"
    shared default GetterScope? getterFor(ValueModel model) {
        value slot = allocations[model];

        if (! exists slot) {
            return null;
        }

        value getterScope = GetterScope(model);
        value offset = getAllocationOffset(slot, getterScope);

        value address = getterScope.addValueInstruction(
                "getelementptr i64, i64* %.context, i64 ``offset``");
        value data = getterScope.addValueInstruction(
                "load i64,i64* ``address``");
        value cast = getterScope.addValueInstruction(
                "inttoptr i64 ``data`` to i64*");
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
        if (!declaration.captured && !declaration.\ishared) {
            if (exists startValue) {
                currentValues.put(declaration, startValue);
            }

            return;
        }

        allocations.put(declaration, allocationBlock++);

        if (! exists startValue) {
            return;
        }

        /* allocationBlock = the new allocation position + 1 */
        value slotOffset = getAllocationOffset(allocationBlock - 1, this);

        value tmp = addValueInstruction("ptrtoint i64* ``startValue`` to i64");
        value offset = addValueInstruction(
                "getelementptr i64, i64* %.frame, i64 ``slotOffset``");
        addInstruction("store i64 ``tmp``, i64* ``offset``");
    }

    "Add instructions to initialize the frame object"
    shared default String initFrame() {
        if (allocationBlock < 0 && !nestedScope) {
            return "    %.frame = bitcast i64* null to i64*\n\n";
        }

        value result = StringBuilder();
        value blocksTotal =
            if (nestedScope)
            then allocationBlock + 1
            else allocationBlock;
        value bytesTotal = blocksTotal * 8;

        result.append("    %.frame = call i64* @malloc(i64 ``bytesTotal``)\n");

        if (nestedScope) {
            result.append("    %.context_cast = \
                           ptrtoint i64* %.context to i64\n");
            result.append("    store i64 %.context_cast, i64* %.frame\n");
        }

        result.append("\n");

        return result.string;
    }

    "Access a declaration"
    shared String access(ValueModel declaration) {
        if (exists cached = currentValues[declaration]) {
            return cached;
        }

        usedItems.add(declaration);

        value context = if (exists f = getFrameFor(declaration))
                        then "i64* ``f``"
                        else "";

        return addValueInstruction(
                "call i64* @``declarationName(declaration)``$get(``context``)");
    }

    "Add a vtable entry for the given declaration model"
    shared default void vtableEntry(DeclarationModel d) {
        "Scope does not cotain a vtable"
        assert(false);
    }

    shared actual default String string {
        value result = StringBuilder();

        beginDefinition(result, modifiers, returnType, definitionName);

        result.append("(");

        if (nestedScope) {
            result.append("i64* %.context");

            if (! arguments.empty) {
                result.append(", ");
            }
        }

        result.append(arguments);
        result.append(") {\n");

        result.append(initFrame());

        for (instruction in instructions) {
            result.append("    ``instruction``\n");
        }

        result.append(postfix);
        result.append("}\n\n");

        return result.string;
    }
}

abstract class CallableScope(DeclarationModel model) extends Scope() {
    shared default String namePostfix = "";
    shared actual Boolean nestedScope = !model.toplevel;
    shared actual String definitionName => declarationName(model) + namePostfix;

    shared actual String? getFrameFor(DeclarationModel declaration) {
        if (is ValueModel declaration, allocates(declaration)) {
            return "%.frame";
        }

        if (declaration.toplevel) {
            return null;
        }

        value container = declaration.container;

        if (container == model) {
            return "%.frame";
        }

        variable Anything visitedContainer = model.container;
        variable String context = "%.context";

        while (is DeclarationModel v = visitedContainer, v != container) {
            value fetch = addValueInstruction("load i64,i64* ``context``");
            context = addValueInstruction("inttoptr i64 ``fetch`` to i64*");

            visitedContainer = v.container;
        }

        "We should always find a parent scope. We'll get to a 'Package' if we
         don't"
        assert(container is DeclarationModel);

        return context;
    }
}

"Scope of a class body"
class ConstructorScope(ClassModel model) extends CallableScope(model) {
    value vtable = ArrayList<DeclarationModel>();
    shared actual String postfix = "    ret void\n";
    shared actual String namePostfix = "$init";
    shared actual String initFrame() => "";
    shared actual String returnType => "void";

    shared actual String getAllocationOffset(Integer slot, Scope scope) {
        value parent = model.extendedType.declaration;

        value shift = scope.addValueInstruction(
                "call i64 @``declarationName(parent)``$size()");
        return scope.addValueInstruction("add i64 ``shift``, ``slot``");
    }

    shared actual String arguments {
        value ret = parameterListToLLVMString(model.parameterList);

        if (ret.empty) {
            return "i64* %.frame";
        }

        return "i64* %.frame, ``ret``";
    }

    String additionalCalls {
        value result = StringBuilder();

        value parent = model.extendedType.declaration;

        beginDefinition(result, modifiers, "i64", declarationName(model) +
                "$size");
        result.append("() {\n");
        result.append("    %.extendedSize = call i64 \
                       @``declarationName(parent)``$size()\n");
        result.append("    %.total = add i64 %.extendedSize, ``allocatedBlocks``");
        result.append("    ret i64 %.total\n}\n\n");

        beginDefinition(result, modifiers, "i64*", declarationName(model));
        result.append("(``parameterListToLLVMString(model.parameterList)``) \
                        {\n");
        result.append("    %.words = call i64 @``declarationName(model)``\
                       $size()\n");
        result.append("    %.bytes = mul i64 %.words, 8\n");
        result.append("    %.frame = call i64* @malloc(i64 %.bytes)\n");

        if (!vtable.empty) {
            result.append("    %.vteptr = getelementptr i64, i64* %.frame, \
                           i64 1\n");
            result.append("    store i64 0, i64* %.vteptr\n");
        }

        result.append("    call void @``declarationName(model)``$init(");
        result.append(arguments);
        result.append(")\n");
        result.append("    ret i64* %.frame\n}\n\n");
        result.append(vtableCode());

        return result.string;
    }

    "Get LLVM code to setup the vtable"
    shared String vtableCode() {
        value result = StringBuilder();
        value parent = model.extendedType.declaration;

        result.append("@``declarationName(model)``$vtable = global i64* \
                       null\n\n");

        result.append("define i64 \
                       @``declarationName(model)``$vtsize() {\n");
        result.append("    %.parentsz = call i64 \
                       @``declarationName(parent)``$vtsize()\n");
        result.append("    %.result = add i64 %.parentsz, ``vtable.size``\n");
        result.append("    ret i64 %.result\n");
        result.append("}\n\n");

        result.append("define private void \
                       @``declarationName(model)``$vtsetup() {\n");
        result.append("    %.parentsz = call i64 \
                       @``declarationName(parent)``$vtsize()\n");
        result.append("    %.size = call i64 \
                       @``declarationName(model)``$vtsize()\n");
        result.append("    %.bytes = mul i64 %.size, 8\n");
        result.append("    %.parentbytes = mul i64 %.parentsz, 8\n");
        result.append("    %.vt = call i64* @malloc(i64 %.bytes)\n");
        result.append("    %.parentvt = load i64*,i64** \
                       @``declarationName(parent)``$vtable\n");
        result.append("    call void @llvm.memcpy.p0i64.p0i64.i64(\
                       i64* %.vt, i64* %.parentvt, i64 %.parentsz, i32 8, \
                       i1 0)\n");
        result.append("    store i64* %.vt, i64** \
                       @``declarationName(model)``$vtable\n");
        result.append("    ret void\n");
        result.append("}\n\n");
        result.append("@llvm.global_ctors = appending global \
                       [1 x %.constructor_type] \
                       [%.constructor_type { \
                       i32 ``vtableConstructorPriority``, \
                       void ()* @``declarationName(model)``$vtsetup }]\n\n");

        return result.string;
    }

    shared actual void vtableEntry(DeclarationModel d)
        => vtable.add(d);

    shared actual String string
        => super.string + additionalCalls + "\n\n";
}

"Scope of a getter method"
class GetterScope(ValueModel model) extends CallableScope(model) {
    shared actual String namePostfix = "$get";
}

"Scope of a setter method"
class SetterScope(ValueModel model) extends CallableScope(model) {
    shared actual String namePostfix = "$set";
}

"The scope of a function"
class FunctionScope(FunctionModel model) extends CallableScope(model) {
    shared actual String postfix => "    ret i64* null\n";
    shared actual String arguments
        => parameterListToLLVMString(model.firstParameterList);
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
        result.append("@llvm.global_ctors = appending global \
                       [1 x %.constructor_type] \
                       [%.constructor_type { \
                       i32 ``toplevelConstructorPriority``, \
                       void ()* @__ceylon_constructor }]\n");
        return result.string;
    }

    shared actual String string
        => globalVariables.string + constructor;

    shared actual GetterScope getterFor(ValueModel model) {
        value getterScope = GetterScope(model);
        value ret = getterScope.addValueInstruction(
                "load i64*,i64** @``declarationName(model)``");
        getterScope.addInstruction("ret i64* ``ret``");
        return getterScope;
    }

    shared actual String? getFrameFor(DeclarationModel declaration) => null;
}
