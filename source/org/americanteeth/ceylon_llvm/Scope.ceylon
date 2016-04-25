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
[AnyLLVMValue*] parameterListToLLVMValues(LLVMFunction func,
        ParameterList parameterList)
    => CeylonList(parameterList.parameters).collect((x)
            => func.register(x.name));

"A scope containing instructions"
abstract class Scope() of CallableScope|UnitScope {
    value getters = ArrayList<LLVMDeclaration>();
    value currentValues = HashMap<ValueModel,Ptr<I64Type>>();
    value allocations = HashMap<ValueModel,Integer>();
    variable value allocationBlock = 0;

    shared Integer allocatedBlocks => allocationBlock;

    shared HashSet<ValueModel> usedItems = HashSet<ValueModel>();

    "Is there an allocation for this value in the frame for this scope"
    shared Boolean allocates(ValueModel v) => allocations.defines(v);

    "Get the frame variable for a nested declaration"
    shared default Ptr<I64Type>? getFrameFor(DeclarationModel declaration) => null;

    "The allocation offset for this item"
    shared default I64 getAllocationOffset(Integer slot, LLVMFunction func)
        => I64Lit(slot+1);

    "Add instructions to fetch an allocated element"
    LLVMFunction getterFor(ValueModel model) {
        assert(exists slot = allocations[model]);

        value getter = LLVMFunction(declarationName(model) + "$get",
                ptr(i64), "", ["i64* %.context"]);

        value offset = getAllocationOffset(slot, getter);

        getter.ret(getter.toPtr(getter.load(getter.register(".context"),
                        offset)));

        return getter;
    }

    "Create space in this scope for a value"
    shared default void allocate(ValueModel declaration,
            Ptr<I64Type>? startValue) {
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

            body.store(
                    body.register(".frame"), body.toI64(startValue),
                    slotOffset);
        }

        getters.add(getterFor(declaration));
    }

    "Access a declaration"
    shared Ptr<I64Type> access(ValueModel declaration) {
        if (exists cached = currentValues[declaration]) {
            return cached;
        }

        usedItems.add(declaration);

        return body.call(ptr(i64), "``declarationName(declaration)``$get",
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
        = LLVMFunction(declarationName(model) + namePostfix, ptr(i64), "",
                if (!model.toplevel)
                then ["i64* %.context"]
                else []);

    shared actual Ptr<I64Type>? getFrameFor(DeclarationModel declaration) {
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
        variable Ptr<I64Type> context = body.register(".context");

        while (is DeclarationModel v = visitedContainer, v != container) {
            context = body.toPtr(body.load(context));
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
        if (model.\iformal || model.\idefault) {
            /* FIXME: SOOO MUCH HACKING */
            value vtable = body.toPtr(body.load(body.register(".context"),
                    I64Lit(1)));

            if (model.\idefault) {
                assert(is DeclarationModel parent = model.container);
                value expectedVt =
                    body.load(body.global(ptr(i64),
                                "``declarationName(parent)``$vtable"));
                body.instruction(
                    "%.dispatchCond = icmp eq ``expectedVt``, \
                     ``vtable.identifier``");
                body.instruction(
                    "br i1 %.dispatchCond, label %.main, label %.dispatch");
                body.instruction(".dispatch:");
            }

            variable value refined = model;

            while (refined.refinedDeclaration != refined) {
                refined = refined.refinedDeclaration;
            }

            value position = body.load(body.global(i64,
                "``declarationName(refined)``$vtPosition"));
            value jumpTargetAsInt = body.load(vtable, position);

            body.instruction(
                    "%.newCall = inttoptr ``jumpTargetAsInt`` to \
                     ``body.llvmType``*");
            body.instruction(
                "%.ret = tail call i64* %.newCall(``body.argList``)");
            body.ret(body.register(".ret"));

            if (model.\idefault) {
                body.instruction(".main:");
            } else {
                body.setInsertPosition();
                return;
            }
        }

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
            body.store(body.register(".frame"),
                    body.toI64(body.register(".context")));
        }
        body.setInsertPosition();
    }
}

"Scope of a class body"
class ConstructorScope(ClassModel model) extends CallableScope(model, "$init") {
    value vtable = ArrayList<DeclarationModel>();
    value vtableOverrides = ArrayList<DeclarationModel>();
    value parent = model.extendedType.declaration;

    {LLVMDeclaration+} globals = [
        LLVMGlobal("``declarationName(model)``$size", I64Lit(0)),
        LLVMGlobal("``declarationName(model)``$vtsize", I64Lit(0)),
        LLVMGlobal(declarationName(model) + "$vtable", llvmNull)
    ];

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
        = LLVMFunction(declarationName(model) + "$init", null, "",
                argumentStrings);

    [AnyLLVMValue*] arguments {
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

        value shift = func.load(func.global(i64,
                    "``declarationName(parent)``$size"));
        value ret = func.add(shift, slot);
        return ret;
    }

    LLVMDeclaration directConstructor() {
        value directConstructor = LLVMFunction(declarationName(model), ptr(i64),
                "", parameterListToLLVMStrings(model.parameterList));
        value size = directConstructor.load(directConstructor.global(i64,
                "``declarationName(model)``$size"));
        value bytes = directConstructor.mul(size, 8);

        directConstructor.instruction(
            "%.frame = call i64* @malloc(``bytes``)");

        value vt = directConstructor.toI64(
                directConstructor.load(directConstructor.global(ptr(i64),
            "``declarationName(model)``$vtable")));
        directConstructor.store(directConstructor.register(".frame"),
                vt, I64Lit(1));

        directConstructor.callVoid("``declarationName(model)``$init",
                *arguments);

        directConstructor.ret(directConstructor.register(".frame"));

        return directConstructor;
    }

    {AnyLLVMGlobal*} vtPositions()
        => vtable.map((x) => LLVMGlobal("``declarationName(x)``$vtPosition",
                    I64Lit(0)));

    shared actual {LLVMDeclaration*} results {
        value setupFunction =
            LLVMFunction(declarationName(model) + "$setupClass",
                    null, "private", []);

        /* Setup size value */
        value sizeGlobal = setupFunction.global(i64,
                "``declarationName(model)``$size");
        value parentSize = setupFunction.load(setupFunction.global(i64,
                "``declarationName(parent)``$size"));
        value size = setupFunction.add(parentSize, allocatedBlocks);
        setupFunction.store(sizeGlobal, size);

        /* Setup vtable size value */
        value vtParentSize = setupFunction.load(setupFunction.global(i64,
                "``declarationName(parent)``$vtsize"));
        value vtParentSizeBytes = setupFunction.mul(vtParentSize, 8);
        value vtSizeGlobal = setupFunction.global(i64,
                "``declarationName(model)``$vtsize");
        value vtSize = setupFunction.add(vtParentSize, vtable.size);
        value vtSizeBytes = setupFunction.mul(vtSize, 8);
        setupFunction.store(vtSizeGlobal, vtSize);

        /* Setup vtable */
        value vt = setupFunction.call(ptr(i64), "malloc", vtSizeBytes);
        value parentvt = setupFunction.load(setupFunction.global(ptr(i64),
                "``declarationName(parent)``$vtable"));
        setupFunction.callVoid("llvm.memcpy.p0i64.p0i64.i64", vt, parentvt,
                vtParentSizeBytes, I32Lit(8), I1Lit(0));

        setupFunction.store(
                setupFunction.global(ptr(i64),
                    "``declarationName(model)``$vtable"), vt);

        /* Set up vtPosition variables */
        variable value i = 0;

        void setVtEntry(DeclarationModel decl, I64 vtPosition) {
            value intValue = setupFunction.registerInt();
            /* FIXME: Hardcoded types and manual instructions and sadness oh
             * my! Seriously though, this code won't work with even slightly
             * more complex dispatch. Just a hack until LLVMCode supports
             * function types somehow.
             */
            setupFunction.instruction(
                    "``intValue.identifier`` = ptrtoint i64*(i64*)* \
                     @``declarationName(decl)`` to i64");
            setupFunction.store(vt, intValue, vtPosition);
        }

        for (decl in vtable) {
            value vtPosition = setupFunction.add(vtParentSize, i++);
            setupFunction.store(
                    setupFunction.global(i64,
                        "``declarationName(decl)``$vtPosition"), vtPosition);

            if (!decl.\idefault) {
                continue;
            }

            setVtEntry(decl, vtPosition);
        }

        /* Set up vtable overrides */
        for (decl in vtableOverrides) {
            variable value rootDecl = decl;

            while (rootDecl.refinedDeclaration != rootDecl) {
                rootDecl = rootDecl.refinedDeclaration;
            }

            value vtPosition = setupFunction.load(setupFunction.global(i64,
                    "``declarationName(rootDecl)``$vtPosition"));

            setVtEntry(decl, vtPosition);
        }

        /* Install setup function as a constructor */
        assert(exists priority = declarationOrder[model]);
        setupFunction.makeConstructor(priority + constructorPriorityOffset);

        return super.results.chain(globals).chain{directConstructor(),
            setupFunction}.chain(vtPositions());
    }

    shared actual void vtableEntry(DeclarationModel d) {
        if (! d.\iactual) {
            vtable.add(d);
        } else {
            vtableOverrides.add(d);
        }
    }
}

"Scope of a getter method"
class GetterScope(ValueModel model) extends CallableScope(model, "$get") {}

"Scope of a setter method"
class SetterScope(ValueModel model) extends CallableScope(model, "$set") {}

"The scope of a function"
class FunctionScope(FunctionModel model) extends CallableScope(model) {
    shared actual LLVMFunction body
        = LLVMFunction(declarationName(model), ptr(i64), "",
                if (!model.toplevel)
                then ["i64* %.context", *parameterListToLLVMStrings(model.firstParameterList)]
                else parameterListToLLVMStrings(model.firstParameterList));
}

"The outermost scope of the compilation unit"
class UnitScope() extends Scope() {
    value globalVariables = ArrayList<AnyLLVMGlobal>();
    value getters = ArrayList<LLVMDeclaration>();

    shared actual LLVMFunction body
        = LLVMFunction("__ceylon_constructor", null, "private", []);

    LLVMFunction getterFor(ValueModel model) {
        value getter = LLVMFunction(declarationName(model) + "$get",
                ptr(i64), "", []);
        value ret = getter.load(getter.global(ptr(i64),
                    declarationName(model)));
        getter.ret(ret);
        return getter;
    }

    shared actual void allocate(ValueModel declaration,
            Ptr<I64Type>? startValue) {
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
