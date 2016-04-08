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
    value getters = ArrayList<LLVMDeclaration>();
    value currentValues = HashMap<ValueModel,String>();
    value allocations = HashMap<ValueModel,Integer>();
    variable value allocationBlock = 0;

    shared Integer allocatedBlocks => allocationBlock;

    shared HashSet<ValueModel> usedItems = HashSet<ValueModel>();

    shared LLVMFunction body => primary;

    "Is there an allocation for this value in the frame for this scope"
    shared Boolean allocates(ValueModel v) => allocations.defines(v);

    "Get the frame variable for a nested declaration"
    shared default String? getFrameFor(DeclarationModel declaration) => null;

    "The allocation offset for this item"
    shared default String getAllocationOffset(Integer slot, LLVMFunction func)
        => (slot+1).string;

    "Add instructions to fetch an allocated element"
    LLVMFunction getterFor(ValueModel model) {
        assert(exists slot = allocations[model]);

        value getter = LLVMFunction(declarationName(model) + "$get",
                "i64*", "", ["i64* %.context"]);

        value offset = getAllocationOffset(slot, getter);

        value address = getter.register().offsetPointer("%.context", offset);
        value data = getter.registerInt().load(address);
        value cast = getter.register().instruction(
                "inttoptr i64 ``data`` to i64*");
        getter.ret(cast);

        return getter;
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

        if (exists startValue) {
            /* allocationBlock = the new allocation position + 1 */
            value slotOffset = getAllocationOffset(allocationBlock - 1,
                    primary);

            value tmp = primary.register().instruction(
                    "ptrtoint i64* ``startValue`` to i64");
            value offset = primary.register().offsetPointer("%.frame",
                    slotOffset);
            primary.instruction("store i64 ``tmp``, i64* ``offset``");
        }

        getters.add(getterFor(declaration));
    }

    "Access a declaration"
    shared String access(ValueModel declaration) {
        if (exists cached = currentValues[declaration]) {
            return cached;
        }

        usedItems.add(declaration);

        return primary.register().call("``declarationName(declaration)``$get",
                *{getFrameFor(declaration)}.coalesced);
    }

    "Add a vtable entry for the given declaration model"
    shared default void vtableEntry(DeclarationModel d) {
        "Scope does not cotain a vtable"
        assert(false);
    }

    shared formal LLVMFunction primary;
    shared default [String*] initFrame() => [];

    shared default {LLVMDeclaration*} results {
        for (i in initFrame()) {
            primary.preamble.instruction(i);
        }
        return {primary, *getters};
    }
}

abstract class CallableScope(DeclarationModel model, String namePostfix = "")
        extends Scope() {
    shared actual default LLVMFunction primary
        = LLVMFunction(declarationName(model) + namePostfix, "i64*", "",
                if (!model.toplevel)
                then ["i64* %.context"]
                else []);

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
            value fetch = primary.registerInt().load(context);
            context = primary.register()
                .instruction("inttoptr i64 ``fetch`` to i64*");

            visitedContainer = v.container;
        }

        "We should always find a parent scope. We'll get to a 'Package' if we
         don't"
        assert(container is DeclarationModel);

        return context;
    }

    "Add instructions to initialize the frame object"
    shared actual default [String*] initFrame() {
        if (allocatedBlocks == 0 && model.toplevel) {
            return ["%.frame = bitcast i64* null to i64*"];
        }

        value blocksTotal =
            if (!model.toplevel)
            then allocatedBlocks + 1
            else allocatedBlocks;
        value bytesTotal = blocksTotal * 8;

        value alloc = "%.frame = call i64* @malloc(i64 ``bytesTotal``)";

        if (model.toplevel) {
            return [alloc];
        }

        return [alloc,
                "%.context_cast = ptrtoint i64* %.context to i64",
                "store i64 %.context_cast, i64* %.frame"];
    }
}

"Scope of a class body"
class ConstructorScope(ClassModel model) extends CallableScope(model, "$init") {
    value vtable = ArrayList<DeclarationModel>();

    shared actual [String*] initFrame() => [];

    [String*] arguments {
        value prepend =
            if (!model.toplevel)
            then ["i64* %.context", "i64* %.frame"]
            else ["i64* %.frame"];

        return prepend.chain(parameterListToLLVMStrings(
                    model.parameterList)).sequence();
    }

    shared actual LLVMFunction primary
        = LLVMFunction(declarationName(model) + "$init", "void", "",
                arguments);

    "The allocation offset for this item"
    shared actual String getAllocationOffset(Integer slot, LLVMFunction func) {
        value parent = model.extendedType.declaration;

        value shift = func.register().instruction(
                "call i64 @``declarationName(parent)``$size()");
        return func.register().instruction("add i64 ``shift``, ``slot``");
    }

    shared actual {LLVMDeclaration*} results {
        value parent = model.extendedType.declaration;

        value sizeFunction = LLVMFunction(declarationName(model) + "$size", "i64",
                "", []);
        sizeFunction.addInstructions(
            "%.extendedSize = call i64 @``declarationName(parent)``$size()",
            "%.total = add i64 %.extendedSize, ``allocatedBlocks``",
            "ret i64 %.total"
        );

        value directConstructor = LLVMFunction(declarationName(model), "i64*",
                "", parameterListToLLVMStrings(model.parameterList));
        directConstructor.addInstructions(
            "%.words = call i64 @``declarationName(model)``$size()",
            "%.bytes = mul i64 %.words, 8\n",
            "%.frame = call i64* @malloc(i64 %.bytes)\n"
        );

        if (!vtable.empty) {
            value vteptr = directConstructor.register().offsetPointer("%.frame",
                    "1");
            directConstructor.instruction("store i64 0, i64* ``vteptr``");
        }

        directConstructor.addInstructions(
            "call void @``declarationName(model)``$init(``", ".join(arguments)``)",
            "ret i64* %.frame"
        );

        value vtSizeFunction = LLVMFunction(declarationName(model) + "$vtsize",
                "i64", "", []);
        vtSizeFunction.addInstructions(
            "%.parentsz = call i64 @``declarationName(parent)``$vtsize()",
            "%.result = add i64 %.parentsz, ``vtable.size``"
        );

        vtSizeFunction.ret("%.result");

        value vtSetupFunction =
            LLVMFunction(declarationName(model) + "$vtsetup",
                    "void", "private", []);
        vtSetupFunction.addInstructions(
            "%.parentsz = call i64 @``declarationName(parent)``$vtsize()",
            "%.size = call i64 @``declarationName(model)``$vtsize()",
            "%.bytes = mul i64 %.size, 8",
            "%.parentbytes = mul i64 %.parentsz, 8",
            "%.vt = call i64* @malloc(i64 %.bytes)");

        vtSetupFunction.register().load("@``declarationName(parent)``$vtable");

        vtSetupFunction.addInstructions(
            "call void @llvm.memcpy.p0i64.p0i64.i64(\
             i64* %.vt, i64* %.parentvt, i64 %.parentsz, i32 8, i1 0)",
            "store i64* %.vt, i64** @``declarationName(model)``$vtable"
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
class GetterScope(ValueModel model) extends CallableScope(model, "$get") {}

"Scope of a setter method"
class SetterScope(ValueModel model) extends CallableScope(model, "$set") {}

"The scope of a function"
class FunctionScope(FunctionModel model) extends CallableScope(model) {
    shared actual LLVMFunction primary
        = LLVMFunction(declarationName(model), "i64*", "",
                if (!model.toplevel)
                then ["i64* %.context", *parameterListToLLVMStrings(model.firstParameterList)]
                else parameterListToLLVMStrings(model.firstParameterList));
}

"The outermost scope of the compilation unit"
class UnitScope() extends Scope() {
    value globalVariables = ArrayList<LLVMGlobal>();
    value getters = ArrayList<LLVMDeclaration>();

    shared actual LLVMFunction primary
        = LLVMFunction("__ceylon_constructor", "void", "private", []);

    LLVMFunction getterFor(ValueModel model) {
        value getter = LLVMFunction(declarationName(model) + "$get",
                "i64*", "", []);
        value ret = getter.register().load("@``declarationName(model)``");
        getter.ret(ret);
        return getter;
    }

    shared actual void allocate(ValueModel declaration,
            String? startValue) {
        value name = declarationName(declaration);

        globalVariables.add(LLVMGlobal(name, startValue));
        getters.add(getterFor(declaration));
    }

    shared actual {LLVMDeclaration*} results {
        value superResults = super.results;

        assert(is LLVMFunction s = superResults.first);
        s.makeConstructor(toplevelConstructorPriority);

        return globalVariables.chain(superResults).chain(getters);
    }
}
