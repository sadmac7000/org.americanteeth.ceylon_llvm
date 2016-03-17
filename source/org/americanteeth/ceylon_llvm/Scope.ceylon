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

"Convert a parameter list to a sequence of LLVM strings"
[String*] parameterListToLLVMStrings(ParameterList parameterList)
    => CeylonList(parameterList.parameters).collect((x) => "i64* %``x.name``");

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
    shared default [String*] arguments = [];

    "Trailing instructions for definition"
    shared default String? postfix = null;

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

    "Add a call instruction"
    shared String addCallInstruction(String type, String name, String* args) {
        return addValueInstruction(
                "call ``type`` @``name``(``", ".join(args)``)");
    }

    "Add a call instruction for a function returning void"
    shared void addVoidCallInstruction(String name, String* args) {
        addInstruction("call void @``name``(``", ".join(args)``)");
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
    shared default [String*] initFrame() {
        if (allocationBlock < 0 && !nestedScope) {
            return ["%.frame = bitcast i64* null to i64*"];
        }

        value blocksTotal =
            if (nestedScope)
            then allocationBlock + 1
            else allocationBlock;
        value bytesTotal = blocksTotal * 8;

        value alloc = "%.frame = call i64* @malloc(i64 ``bytesTotal``)";

        if (! nestedScope) {
            return [alloc];
        }

        return [alloc,
                "%.context_cast = ptrtoint i64* %.context to i64",
                "store i64 %.context_cast, i64* %.frame"];
    }

    "Access a declaration"
    shared String access(ValueModel declaration) {
        if (exists cached = currentValues[declaration]) {
            return cached;
        }

        usedItems.add(declaration);

        value context = if (exists f = getFrameFor(declaration))
                        then {"i64* ``f``"}
                        else {""};

        return addCallInstruction("i64*",
                "``declarationName(declaration)``$get", *context);
    }

    "Add a vtable entry for the given declaration model"
    shared default void vtableEntry(DeclarationModel d) {
        "Scope does not cotain a vtable"
        assert(false);
    }

    shared default {LLVMDeclaration*} results {
        value fullArguments =
            if (nestedScope)
            then ["i64* %.context", *arguments]
            else arguments;

        value llvmFunction = LLVMFunction(definitionName, returnType,
                modifiers, fullArguments, [*initFrame().chain(instructions)]);

        if (exists p = postfix) {
            llvmFunction.addInstructions(p);
        }

        return {llvmFunction};
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
    shared actual String postfix = "ret void";
    shared actual String namePostfix = "$init";
    shared actual [String*] initFrame() => [];
    shared actual String returnType => "void";

    shared actual String getAllocationOffset(Integer slot, Scope scope) {
        value parent = model.extendedType.declaration;

        value shift = scope.addCallInstruction("i64",
                "``declarationName(parent)``$size");
        return scope.addValueInstruction("add i64 ``shift``, ``slot``");
    }

    shared actual [String*] arguments
        => ["i64* %.frame", *parameterListToLLVMStrings(model.parameterList)];

    shared actual {LLVMDeclaration*} results {
        value parent = model.extendedType.declaration;

        value sizeFunction = LLVMFunction(declarationName(model) + "$size", "i64",
                modifiers, [], []);
        sizeFunction.addInstructions(
            "%.extendedSize = call i64 @``declarationName(parent)``$size()",
            "%.total = add i64 %.extendedSize, ``allocatedBlocks``",
            "ret i64 %.total"
        );

        value directConstructor = LLVMFunction(declarationName(model), "i64*",
                modifiers, parameterListToLLVMStrings(model.parameterList), []);
        directConstructor.addInstructions(
            "%.words = call i64 @``declarationName(model)``$size()",
            "%.bytes = mul i64 %.words, 8\n",
            "%.frame = call i64* @malloc(i64 %.bytes)\n"
        );

        if (!vtable.empty) {
            directConstructor.addInstructions(
                "%.vteptr = getelementptr i64, i64* %.frame, i64 1",
                "store i64 0, i64* %.vteptr"
            );
        }

        directConstructor.addInstructions(
            "call void @``declarationName(model)``$init(``", ".join(arguments)``)",
            "ret i64* %.frame"
        );

        value vtSizeFunction = LLVMFunction(declarationName(model) + "$vtsize",
                "i64", "", [], []);
        vtSizeFunction.addInstructions(
            "%.parentsz = call i64 @``declarationName(parent)``$vtsize()",
            "%.result = add i64 %.parentsz, ``vtable.size``",
            "ret i64 %.result"
        );

        value vtSetupFunction =
            LLVMFunction(declarationName(model) + "$vtsetup",
                    "void", "private", [], []);
        vtSetupFunction.addInstructions(
            "%.parentsz = call i64 @``declarationName(parent)``$vtsize()",
            "%.size = call i64 @``declarationName(model)``$vtsize()",
            "%.bytes = mul i64 %.size, 8",
            "%.parentbytes = mul i64 %.parentsz, 8",
            "%.vt = call i64* @malloc(i64 %.bytes)",
            "%.parentvt = load i64*,i64** @``declarationName(parent)``$vtable",
            "call void @llvm.memcpy.p0i64.p0i64.i64(\
             i64* %.vt, i64* %.parentvt, i64 %.parentsz, i32 8, i1 0)",
            "store i64* %.vt, i64** @``declarationName(model)``$vtable",
            "ret void"
        );

        vtSetupFunction.makeConstructor(vtableConstructorPriority);

        value vtableCode = LLVMGlobal(declarationName(model) + "$vtable");

        return super.results.chain{sizeFunction, directConstructor, vtableCode,
            vtSizeFunction, vtSetupFunction};
    }

    shared actual void vtableEntry(DeclarationModel d)
        => vtable.add(d);
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
    shared actual String postfix => "ret i64* null";
    shared actual [String*] arguments
        => parameterListToLLVMStrings(model.firstParameterList);
}

"The outermost scope of the compilation unit"
class UnitScope() extends Scope() {
    value globalVariables = ArrayList<LLVMGlobal>();
    shared actual String definitionName => "__ceylon_constructor";
    shared actual String modifiers => "private";
    shared actual String returnType => "void";
    shared actual String postfix => "ret void";

    shared actual void allocate(ValueModel declaration,
            String? startValue) {
        value name = namePrefix(declaration);

        globalVariables.add(LLVMGlobal(name, startValue));
    }

    shared actual {LLVMDeclaration*} results {
        value superResults = super.results;

        assert(is LLVMFunction s = superResults.first);
        s.makeConstructor(toplevelConstructorPriority);

        return globalVariables.chain(superResults);
    }

    shared actual GetterScope getterFor(ValueModel model) {
        value getterScope = GetterScope(model);
        value ret = getterScope.addValueInstruction(
                "load i64*,i64** @``declarationName(model)``");
        getterScope.addInstruction("ret i64* ``ret``");
        return getterScope;
    }

    shared actual String? getFrameFor(DeclarationModel declaration) => null;
}
