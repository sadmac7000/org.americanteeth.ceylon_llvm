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

"Floor value for constructor function priorities. We use this just to be well
 out of the way of any C libraries that might get linked with us."
Integer constructorPriorityOffset = 65536;

"Priority of the library constructor function that contains all of the toplevel
 code. Maximum inheritance depth is effectively bounded by this value, as
 vtable initializers are expected to have values equal to the declared item's
 inheritance depth."
Integer toplevelConstructorPriority = constructorPriorityOffset + 65535;

"Convert a parameter list to a sequence of LLVM strings"
[String*] parameterListToLLVMStrings(ParameterList parameterList)
    => CeylonList(parameterList.parameters).collect((x) => "i64* %``x.name``");

"Convert a parameter list to a sequence of LLVM values"
[LLVMValue*] parameterListToLLVMValues(LLVMFunction func,
        ParameterList parameterList)
    => CeylonList(parameterList.parameters).collect((x)
            => func.register(x.name));

"A scope containing instructions"
abstract class Scope() of CallableScope|UnitScope {
    value getters = ArrayList<LLVMDeclaration>();
    value currentValues = HashMap<ValueModel,Ptr<I64>>();
    value allocations = HashMap<ValueModel,Integer>();
    variable value allocationBlock = 0;

    shared Integer allocatedBlocks => allocationBlock;

    shared HashSet<ValueModel> usedItems = HashSet<ValueModel>();

    "Is there an allocation for this value in the frame for this scope"
    shared Boolean allocates(ValueModel v) => allocations.defines(v);

    "Get the frame variable for a nested declaration"
    shared default Ptr<I64>? getFrameFor(DeclarationModel declaration) => null;

    "The allocation offset for this item"
    shared default I64 getAllocationOffset(Integer slot, LLVMFunction func)
        => I64Lit(slot+1);

    "Add instructions to fetch an allocated element"
    LLVMFunction getterFor(ValueModel model) {
        assert(exists slot = allocations[model]);

        value getter = LLVMFunction(declarationName(model) + "$get",
                "i64*", "", ["i64* %.context"]);

        value offset = getAllocationOffset(slot, getter);

        getter.ret(getter.register(".context").load(offset).i64p());

        return getter;
    }

    "Create space in this scope for a value"
    shared default void allocate(ValueModel declaration,
            Ptr<I64>? startValue) {
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
                    body);

            body.register(".frame").store(startValue.i64(), slotOffset);
        }

        getters.add(getterFor(declaration));
    }

    "Access a declaration"
    shared Ptr<I64> access(ValueModel declaration) {
        if (exists cached = currentValues[declaration]) {
            return cached;
        }

        usedItems.add(declaration);

        return body.call<Ptr<I64>>("``declarationName(declaration)``$get",
                *{getFrameFor(declaration)}.coalesced);
    }

    "Add a vtable entry for the given declaration model"
    shared default void vtableEntry(DeclarationModel d) {
        "Scope does not cotain a vtable"
        assert(false);
    }

    shared formal LLVMFunction body;
    shared default void initFrame() {}

    shared default {LLVMDeclaration*} results {
        initFrame();
        return {body, *getters};
    }
}

abstract class CallableScope(DeclarationModel model, String namePostfix = "")
        extends Scope() {
    shared actual default LLVMFunction body
        = LLVMFunction(declarationName(model) + namePostfix, "i64*", "",
                if (!model.toplevel)
                then ["i64* %.context"]
                else []);

    shared actual Ptr<I64>? getFrameFor(DeclarationModel declaration) {
        if (is ValueModel declaration, allocates(declaration)) {
            return body.register(".frame");
        }

        if (declaration.toplevel) {
            return null;
        }

        value container = declaration.container;

        if (container == model) {
            return body.register(".frame");
        }

        variable Anything visitedContainer = model.container;
        variable Ptr<I64> context = body.register(".context");

        while (is DeclarationModel v = visitedContainer, v != container) {
            context = context.load().i64p();
            visitedContainer = v.container;
        }

        "We should always find a parent scope. We'll get to a 'Package' if we
         don't"
        assert(container is DeclarationModel);

        return context;
    }

    "Add instructions to initialize the frame object"
    shared actual default void initFrame() {
        body.setInsertPosition(0);
        if (allocatedBlocks == 0 && model.toplevel) {
            body.instruction("%.frame = bitcast i64* null to i64*");
            body.setInsertPosition();
            return;
        }

        value blocksTotal =
            if (!model.toplevel)
            then allocatedBlocks + 1
            else allocatedBlocks;
        value bytesTotal = blocksTotal * 8;

        body.instruction("%.frame = call i64* @malloc(i64 ``bytesTotal``)");

        if (!model.toplevel) {
            body.register(".frame").store(body.register(".context").i64());
        }
        body.setInsertPosition();
    }
}

"Scope of a class body"
class ConstructorScope(ClassModel model) extends CallableScope(model, "$init") {
    value vtable = ArrayList<DeclarationModel>();

    shared actual void initFrame() {}

    [String*] argumentStrings {
        value prepend =
            if (!model.toplevel)
            then ["i64* %.context", "i64* %.frame"]
            else ["i64* %.frame"];

        return prepend.chain(parameterListToLLVMStrings(
                    model.parameterList)).sequence();
    }

    shared actual LLVMFunction body
        = LLVMFunction(declarationName(model) + "$init", "void", "",
                argumentStrings);

    [LLVMValue*] arguments {
        value prepend =
            if (!model.toplevel)
            then [body.register(".context"), body.register(".frame")]
            else [body.register(".frame")];

        return prepend.chain(parameterListToLLVMValues(body,
                    model.parameterList)).sequence();
    }

    "The allocation offset for this item"
    shared actual I64 getAllocationOffset(Integer slot, LLVMFunction func) {
        value parent = model.extendedType.declaration;

        value shift = func.global<I64>("``declarationName(parent)``$size").load();
        value ret = func.add(shift, slot);
        return ret;
    }

    shared actual {LLVMDeclaration*} results {
        value parent = model.extendedType.declaration;

        value sizeDecl = LLVMGlobal("``declarationName(model)``$size",
                I64Lit(0));

        value directConstructor = LLVMFunction(declarationName(model), "i64*",
                "", parameterListToLLVMStrings(model.parameterList));
        value bytes = directConstructor.global<I64>(
                "``declarationName(model)``$size").load();
        directConstructor.instruction(
            "%.frame = call i64* @malloc(``bytes``)");

        if (!vtable.empty) {
            directConstructor.register(".frame").store(I64Lit(0), I64Lit(1));
        }

        directConstructor.call<>("``declarationName(model)``$init",
                *arguments);

        directConstructor.ret(directConstructor.register(".frame"));

        value vtSizeDecl = LLVMGlobal("``declarationName(model)``$vtsize",
                I64Lit(0));

        value setupFunction =
            LLVMFunction(declarationName(model) + "$setupClass",
                    "void", "private", []);

        /* Setup size value */
        value sizeGlobal = setupFunction.global<I64>(
                "``declarationName(model)``$size");
        value parentSize = setupFunction.global<I64>(
                "``declarationName(parent)``$size").load();
        value sizeValue = setupFunction.add(parentSize, allocatedBlocks * 8);
        sizeGlobal.store(sizeValue);


        /* Setup vtable size value */
        value vtparentsz = setupFunction.global<I64>(
                "``declarationName(parent)``$vtsize").load();
        value vtSizeGlobal = setupFunction.global<I64>(
                "``declarationName(model)``$vtsize");
        value size = setupFunction.add(vtparentsz, vtable.size * 8);
        vtSizeGlobal.store(size);

        /* Setup vtable */
        value vt = setupFunction.call<Ptr<I64>>("malloc", size);
        value parentvt = setupFunction.global<Ptr<I64>>(
                "``declarationName(parent)``$vtable").load();
        setupFunction.call<>("llvm.memcpy.p0i64.p0i64.i64", vt, parentvt,
                vtparentsz, I32Lit(8), I1Lit(0));

        setupFunction.global<Ptr<I64>>("``declarationName(model)``$vtable")
            .store(vt);

        assert(exists priority = declarationOrder[model]);
        setupFunction.makeConstructor(priority + constructorPriorityOffset);

        value vtableDecl = LLVMGlobal(declarationName(model) + "$vtable");

        return super.results.chain{sizeDecl, directConstructor, vtableDecl,
            vtSizeDecl, setupFunction};
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
    shared actual LLVMFunction body
        = LLVMFunction(declarationName(model), "i64*", "",
                if (!model.toplevel)
                then ["i64* %.context", *parameterListToLLVMStrings(model.firstParameterList)]
                else parameterListToLLVMStrings(model.firstParameterList));
}

"The outermost scope of the compilation unit"
class UnitScope() extends Scope() {
    value globalVariables = ArrayList<LLVMGlobal>();
    value getters = ArrayList<LLVMDeclaration>();

    shared actual LLVMFunction body
        = LLVMFunction("__ceylon_constructor", "void", "private", []);

    LLVMFunction getterFor(ValueModel model) {
        value getter = LLVMFunction(declarationName(model) + "$get",
                "i64*", "", []);
        value ret = getter.global<Ptr<I64>>(declarationName(model)).load();
        getter.ret(ret);
        return getter;
    }

    shared actual void allocate(ValueModel declaration,
            Ptr<I64>? startValue) {
        value name = declarationName(declaration);

        globalVariables.add(LLVMGlobal(name, startValue else llvmNull));
        getters.add(getterFor(declaration));
    }

    shared actual {LLVMDeclaration*} results {
        value superResults = super.results;

        assert(is LLVMFunction s = superResults.first);
        s.makeConstructor(toplevelConstructorPriority);

        return globalVariables.chain(superResults).chain(getters);
    }
}
