import ceylon.ast.core {
    ...
}

import ceylon.interop.java {
    CeylonList
}

import ceylon.collection {
    ArrayList,
    HashMap
}

import com.redhat.ceylon.compiler.typechecker.tree {
    Tree
}

import com.redhat.ceylon.model.typechecker.model {
    FunctionModel=Function,
    ValueModel=Value,
    ClassModel=Class,
    InterfaceModel=Interface,
    PackageModel=Package
}

class LLVMBuilder(String triple, PackageModel languagePackage)
        satisfies WideningTransformer<AnyLLVMValue?> {
    "Nodes to handle by just transforming all children"
    alias StandardNode =>
        ClassBody|InterfaceBody|ExpressionStatement|
        Block|CompilationUnit|InvocationStatement;

    "Nodes to ignore completely"
    alias IgnoredNode =>
        Import|ModuleCompilationUnit|PackageCompilationUnit|Annotations;

    "The next string literal ID available"
    variable value nextStringLiteral = 0;

    "A table of all string literals"
    value stringLiterals = HashMap<Integer,String>();

    "LLVM text for the string table"
    String stringTable {
        value result = StringBuilder();

        for (id->raw in stringLiterals) {
            value [str, sz] = processEscapes(raw);
            result.append("@.str``id``.data = private unnamed_addr constant \
                           [``sz`` x i8] c\"``str``\"
                           @.str``id``.object = private unnamed_addr constant \
                           [3 x i64] [i64 0, i64 ``sz``, \
                           i64 ptrtoint([``sz`` x i8]* @.str``id``.data to i64)]
                           @.str``id`` = private alias i64,i64* \
                           bitcast([3 x i64]* @.str``id``.object to i64*)\n\n"
            );
        }

        return result.string;
    }

    "Prefix for all units"
    String preamble = "%.constructor_type = type { i32, void ()* }
                       target triple = \"``triple``\"\n\n";

    "The run() method"
    variable FunctionModel? runSymbol = null;

    "Emitted LLVM for the run() method alias"
    String runSymbolAlias
            => if (exists r = runSymbol)
            then "@__ceylon_run = alias i64*(),i64*()* @``declarationName(r)``\n"
            else "";

    "Top-level scope of the compilation unit"
    value unitScope = UnitScope();

    "The code we are outputting"
    value output = LLVMUnit();

    shared actual String string {
        for (item in unitScope.results) {
            output.append(item);
        }

        return preamble + stringTable + output.string +
                runSymbolAlias;
    }

    "Stack of declarations we are processing"
    value scopeStack = ArrayList<Scope>();

    "The current scope"
    value scope => scopeStack.last else unitScope;

    "Push a new scope"
    T push<T>(T m) given T satisfies Scope {
        scopeStack.add(m);
        return m;
    }

    "pop a scope"
    void pop(Scope check) {
        "We must pop no more scopes than we push"
        assert (exists scope = scopeStack.deleteLast());

        "We did not pop the scope we expected"
        assert(scope == check);

        for (result in scope.results) {
            output.append(result);
        }
    }

    GetterScope getterScope(ValueModel model) => push(GetterScope(model, pop));
    SetterScope setterScope(ValueModel model) => push(SetterScope(model, pop));
    ConstructorScope constructorScope(ClassModel model) => push(ConstructorScope(model, pop));
    FunctionScope functionScope(FunctionModel model) => push(FunctionScope(model, pop));
    InterfaceScope interfaceScope(InterfaceModel model) => push(InterfaceScope(model, pop));

    shared actual AnyLLVMValue? transformNode(Node that) {
        if (is IgnoredNode that) {
            return null;
        }

        if (!is StandardNode that) {
            throw UnsupportedNode(that);
        }

        return that.transformChildren(this).last;
    }

    shared actual Null transformAnyValue(AnyValue that) {
        "Should have an AttributeDeclaration from the type checker"
        assert (is Tree.AnyAttribute tc = that.get(keys.tcNode));

        "All AnyAttribute nodes should be value declarations"
        assert (is ValueModel model = tc.declarationModel);

        value specifier = that.definition;

        if (exists specifier, !is Specifier specifier) {
            try (getterScope(model)) {
                specifier.transform(this);
            }

            return null;
        }

        assert (is Specifier? specifier);

        Ptr<I64Type>? initialValue;
        if (exists specifier) {
            assert(is Ptr<I64Type> i = specifier.expression.transform(this));
            initialValue = i;
        } else {
            initialValue = null;
        }

        scope.allocate(model, initialValue);
        return null;
    }

    shared actual Ptr<I64Type> transformStringLiteral(StringLiteral that) {
        value idNumber = nextStringLiteral++;
        stringLiterals.put(idNumber, that.text);
        return scope.body.global(i64, ".str``idNumber``");
    }

    shared actual Null transformObjectDefinition(ObjectDefinition that) {
        assert(is Tree.ObjectDefinition tc = that.get(keys.tcNode));

        try (constructorScope(tc.anonymousClass)) {
            that.extendedType?.transform(this);
            that.body.transform(this);
        }

        value val = scope.body.call(ptr(i64),
                declarationName(tc.anonymousClass));
        scope.allocate(tc.declarationModel, null);
        scope.body.storeGlobal(declarationName(tc.declarationModel), val);

        return null;
    }

    shared actual Null transformClassDefinition(ClassDefinition that) {
        assert (is Tree.ClassDefinition tc = that.get(keys.tcNode));
        value model = tc.declarationModel;

        try (constructorScope(tc.declarationModel)) {
            for (parameter in CeylonList(model.parameterList.parameters)) {
                assert (is ValueModel v = parameter.model);
                scope.allocate(v, scope.body.register(ptr(i64), parameter.name));
            }

            that.extendedType?.transform(this);
            that.body.transform(this);
        }

        return null;
    }

    shared actual Null transformExtendedType(ExtendedType that) {
        value target = that.target;
        assert (is Tree.InvocationExpression tc = target.get(keys.tcNode));
        assert (is Tree.ExtendedTypeExpression te = tc.primary);

        value arguments = ArrayList<Ptr<I64Type>>();

        if (exists argNode = target.arguments) {
            for (argument in argNode.argumentList.children) {
                "Arguments must have a value"
                assert (is Ptr<I64Type> l = argument.transform(this));
                arguments.add(l);
            }
        }

        scope.body.callVoid(initializerName(te.declaration),
            scope.body.register(ptr(i64), frameName), *arguments);

        return null;
    }

    shared actual Null transformLazySpecifier(LazySpecifier that) {
        "Lazy Specifier expression should have a value"
        assert (is Ptr<I64Type> l = that.expression.transform(this));

        scope.body.ret(l);

        return null;
    }

    shared actual Null transformInterfaceDefinition(InterfaceDefinition that) {
        assert(is Tree.InterfaceDefinition tc = that.get(keys.tcNode));
        try (interfaceScope(tc.declarationModel)) {
            that.body.transform(this);
        }

        return null;
    }

    shared actual Null transformReturn(Return that) {
        Ptr<I64Type> val;
        if (!that.result exists) {
            val = llvmNull;
        } else {
            "Returned expression should have a value"
            assert (is Ptr<I64Type> l = that.result?.transform(this));
            val = l;
        }

        scope.body.ret(val);
        return null;
    }

    shared actual Null transformAnyFunction(AnyFunction that) {
        assert (is Tree.AnyMethod tc = that.get(keys.tcNode));

        if (tc.declarationModel.name == "run",
            tc.declarationModel.container is PackageModel) {
            runSymbol = tc.declarationModel;
        }

        /* TODO: */
        "We don't support multiple parameter lists yet."
        assert (that.parameterLists.size == 1);

        value firstParameterList = tc.declarationModel.firstParameterList;

        if (tc.declarationModel.\iformal || tc.declarationModel.\idefault) {
            output.append(vtDispatchFunction(tc.declarationModel));
        }

        if (tc.declarationModel.\iformal) {
            return null;
        }

        try (functionScope(tc.declarationModel)) {
            for (parameter in CeylonList(firstParameterList.parameters)) {
                assert (is ValueModel v = parameter.model);
                scope.allocate(v, scope.body.register(ptr(i64),
                            parameter.name));
            }

            that.definition?.transform(this);
        }

        return null;
    }

    shared actual Ptr<I64Type> transformInvocation(Invocation that) {
        "We don't support expression callables yet"
        assert (is BaseExpression|QualifiedExpression b = that.invoked);

        "Base expressions should have Base Member or Base Type RH nodes"
        assert (is Tree.MemberOrTypeExpression bt = b.get(keys.tcNode));
        value arguments = ArrayList<Ptr<I64Type>>();

        "We don't support named arguments yet"
        assert (is PositionalArguments pa = that.arguments);

        "We don't support sequence arguments yet"
        assert (!pa.argumentList.sequenceArgument exists);

        value sup = if (is QualifiedExpression b, b.receiverExpression is Super)
            then true else false;

        if (is QualifiedExpression b,
            ! b.receiverExpression is Super|Package|This) {
            assert (is Ptr<I64Type> l = b.receiverExpression.transform(this));
            arguments.add(l);
        } else if (exists f = scope.getContextFor(bt.declaration, sup)) {
            arguments.add(f);
        }

        String functionName;

        if (is QualifiedExpression b, b.receiverExpression is Super) {
            functionName = dispatchName(bt.declaration);
        } else {
            functionName = declarationName(bt.declaration);
        }

        for (arg in pa.argumentList.listedArguments) {
            "Arguments should have a value"
            assert (is Ptr<I64Type> l = arg.transform(this));
            arguments.add(l);
        }

        return scope.body.call(ptr(i64), functionName, *arguments);
    }

    shared actual Ptr<I64Type> transformBaseExpression(BaseExpression that) {
        assert (is Tree.BaseMemberExpression tb = that.get(keys.tcNode));
        assert (is ValueModel declaration = tb.declaration);
        return scope.access(declaration);
    }

    shared actual Ptr<I64Type> transformQualifiedExpression(QualifiedExpression that) {
        "TODO: Support fancy member operators"
        assert (that.memberOperator is MemberOperator);

        assert (is Tree.QualifiedMemberOrTypeExpression tc =
                that.get(keys.tcNode));

        assert (is Ptr<I64Type> target =
                that.receiverExpression.transform(this));

        return scope.body.call(ptr(i64), getterName(tc.declaration), target);
    }

    shared actual Ptr<I64Type> transformThis(This that) {
        assert (is Tree.This tc = that.get(keys.tcNode));
        "Contexts where `this` appears should always have a frame"
        assert(exists s = scope.getFrameFor(tc.declarationModel));
        return s;
    }

    shared actual Ptr<I64Type> transformOuter(Outer that) {
        assert (is Tree.Outer tc = that.get(keys.tcNode));
        "Contexts where `outer` appears should always have a frame"
        assert(exists s = scope.getFrameFor(tc.declarationModel));
        return s;
    }

    shared actual Null transformForFail(ForFail that) {
        assert(is Ptr<I64Type> iterated =
                that.forClause.iterator.iterated.transform(this));

        /* TODO: Widen this assertion once we figure out how the hell the type
         * hierarchy is shaped.
         */
        assert(is Tree.BaseMemberExpression tc =
                that.forClause.iterator.iterated.get(keys.tcNode));
        value iteratedDec = tc.typeModel.declaration;
        value iteratorGetter = iteratedDec.getMember("iterator", null, false);
        assert(is FunctionModel iteratorGetter);
        value iteratorType = iteratorGetter.type.declaration;
        value iteratorNext = iteratorType.getDirectMember("next", null, false);
        value finishedDec = languagePackage.getDirectMember("finished", null,
                false);
        value finishedVal = scope.body.call(ptr(i64), getterName(finishedDec));

        value iterator = scope.body.call(ptr(i64),
                declarationName(iteratorGetter));

        value loopStart = scope.body.splitBlock();

        value nextValue = scope.body.call(ptr(i64),
                declarationName(iteratorNext), iterator);

        value comparison = scope.body.compareEq(nextValue, finishedVal);
        value [loopEnd, loopBody] = scope.body.branch(comparison);

        Label breakPosition;

        if (exists f = that.failClause) {
            scope.body.block = loopEnd;
            f.block.transform(this);
            breakPosition = scope.body.splitBlock();
        } else {
            breakPosition = loopEnd;
        }

        scope.body.block = loopBody;

        try (scope.LoopContext(loopStart, breakPosition)) {
            that.forClause.block.transform(this);
        }

        scope.body.jump(loopStart);

        scope.body.block = breakPosition;
        return null;
    }

    shared actual Null transformBreak(Break that) {
        scope.breakLoop();
        return null;
    }

    shared actual Null transformContinue(Continue that) {
        scope.continueLoop();
        return null;
    }

    shared actual Null transformIfElse(IfElse that) {
        value checkPosition = scope.body.block;
        value trueBlock = scope.body.newBlock();
        value falseBlock = scope.body.newBlock();

        scope.body.block = trueBlock;
        that.ifClause.block.transform(this);
        value trueBlockEnd = if (scope.body.blockTerminated())
            then null
            else scope.body.block;

        scope.body.block = falseBlock;

        if (exists elseClause = that.elseClause) {
            elseClause.transform(this);
        }

        value falseBlockEnd = scope.body.splitBlock();

        if (exists trueBlockEnd, !scope.body.blockTerminated(trueBlockEnd)) {
            scope.body.block = trueBlockEnd;
            scope.body.jump(falseBlockEnd);
        }

        scope.body.block = checkPosition;
        value lastCodition = that.ifClause.conditions.conditions.last;

        for (condition in that.ifClause.conditions.conditions) {
            assert(is I1 conditionValue = condition.transform(this));

            Label? next = if (lastCodition == condition)
                then trueBlock else null;

            value [_, nextBlock] = scope.body.branch(conditionValue, next,
                    falseBlock);
            scope.body.block = nextBlock;
        }

        scope.body.block = falseBlockEnd;
        return null;
    }

    shared actual I1 transformBooleanCondition(BooleanCondition that) {
        assert(is Ptr<I64Type> booleanValue = that.condition.transform(this));
        value trueDeclaration = languagePackage.getDirectMember("true", null,
                false);
        value trueValue = scope.body.call(ptr(i64),
                getterName(trueDeclaration));
        return scope.body.compareEq(booleanValue, trueValue);
    }
}
