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

        value data = getter.register("context").fetch(offset);
        value cast = getter.register();
        cast.instruction("inttoptr ``data`` to i64*");
        getter.ret(cast);

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

            value tmp = body.registerInt();
            tmp.instruction("ptrtoint ``startValue`` to i64");
            value offset = body.register("frame").offset(slotOffset);
            body.instruction("store ``tmp``, ``offset``");
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
    shared default [String*] initFrame() => [];

    shared default {LLVMDeclaration*} results {
        for (i in initFrame()) {
            body.preamble.instruction(i);
        }

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
            return body.register("frame");
        }

        if (declaration.toplevel) {
            return null;
        }

        value container = declaration.container;

        if (container == model) {
            return body.register("frame");
        }

        variable Anything visitedContainer = model.container;
        variable Ptr<I64> context = body.register("context");

        while (is DeclarationModel v = visitedContainer, v != container) {
            value fetch = context.fetch();
            context = body.register();
            context.instruction("inttoptr ``fetch`` to i64*");

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

    shared actual LLVMFunction body
        = LLVMFunction(declarationName(model) + "$init", "void", "",
                arguments);

    "The allocation offset for this item"
    shared actual I64 getAllocationOffset(Integer slot, LLVMFunction func) {
        value parent = model.extendedType.declaration;

        value shift = func.registerInt();
        shift.instruction("call i64 @``declarationName(parent)``$size()");
        value ret = func.registerInt();
        ret.instruction("add ``shift``, ``slot``");
        return ret;
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
            value vteptr = directConstructor.register("frame").offset(I64Lit(1));
            directConstructor.instruction("store i64 0, ``vteptr``");
        }

        directConstructor.addInstructions(
            "call void @``declarationName(model)``$init(``", ".join(arguments)``)",
            "ret i64* %.frame"
        );

        value vtSizeFunction = LLVMFunction(declarationName(model) + "$vtsize",
                "i64", "", []);
        value parentsz = vtSizeFunction.registerInt();
        parentsz.instruction("call i64 @``declarationName(parent)``$vtsize()");
        value result = vtSizeFunction.registerInt();
        result.instruction("add ``parentsz``, ``vtable.size``");
        vtSizeFunction.ret(result);

        value vtSetupFunction =
            LLVMFunction(declarationName(model) + "$vtsetup",
                    "void", "private", []);
        vtSetupFunction.addInstructions(
            "%.parentsz = call i64 @``declarationName(parent)``$vtsize()",
            "%.size = call i64 @``declarationName(model)``$vtsize()",
            "%.bytes = mul i64 %.size, 8",
            "%.parentbytes = mul i64 %.parentsz, 8",
            "%.vt = call i64* @malloc(i64 %.bytes)");

        value parentvt = vtSetupFunction.global<Ptr<I64>>(
                "``declarationName(parent)``$vtable").fetch();

        vtSetupFunction.addInstructions(
            "call void @llvm.memcpy.p0i64.p0i64.i64(\
             i64* %.vt, ``parentvt``, i64 %.parentsz, i32 8, i1 0)",
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
        value ret = getter.global<Ptr<I64>>(declarationName(model)).fetch();
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
