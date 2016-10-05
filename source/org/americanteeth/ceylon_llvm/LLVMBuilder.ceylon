import ceylon.ast.core {
    ...
}

import ceylon.interop.java {
    CeylonList
}

import ceylon.collection {
    ArrayList
}

import com.redhat.ceylon.compiler.typechecker.tree {
    Tree
}

import com.redhat.ceylon.model.typechecker.model {
    FunctionModel=Function,
    ValueModel=Value,
    ClassModel=Class,
    InterfaceModel=Interface,
    SetterModel=Setter,
    PackageModel=Package
}

class LLVMBuilder(String triple, PackageModel languagePackage)
        satisfies Visitor {
    "Nodes to handle by just visiting all children"
    alias StandardNode =>
        ClassBody|InterfaceBody|CompilationUnit|Block;

    "Nodes to handle by just visiting all children as expressions."
    alias ExpressionNode => ExpressionStatement|InvocationStatement;

    "Nodes to ignore completely"
    alias IgnoredNode =>
        Import|ModuleCompilationUnit|PackageCompilationUnit|Annotations;

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

    "Stack of declarations we are processing"
    value scopeStack = ArrayList<Scope>();

    "The current scope"
    Scope scope => scopeStack.last else unitScope;

    "Our expression transformer"
    value expressionTransformer =
        ExpressionTransformer(() => scope, languagePackage);

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
    SetterScope setterScope(SetterModel model) => push(SetterScope(model, pop));
    ConstructorScope constructorScope(ClassModel model) => push(ConstructorScope(model, pop));
    FunctionScope functionScope(FunctionModel model) => push(FunctionScope(model, pop));
    InterfaceScope interfaceScope(InterfaceModel model) => push(InterfaceScope(model, pop));

    shared actual String string {
        for (item in unitScope.results) {
            output.append(item);
        }

        return preamble + expressionTransformer.stringTable() + output.string +
                runSymbolAlias;
    }

    shared actual void visitNode(Node that) {
        if (is IgnoredNode that) {
            return;
        } else if (is StandardNode that) {
            that.visitChildren(this);
        } else if (is ExpressionNode that) {
            that.transformChildren(expressionTransformer);
        } else {
            throw UnsupportedNode(that);
        }
    }

    shared actual void visitValueSpecification(ValueSpecification that) {
        assert(is Tree.SpecifierStatement tc = that.get(keys.tcNode));

        assert(is ValueModel model = tc.declaration);
        value setting =
            that.specifier.expression.transform(expressionTransformer);

        scope.allocate(model, setting);
    }

    shared actual void visitLazySpecification(LazySpecification that) {
        assert(is Tree.SpecifierStatement tc = that.get(keys.tcNode));

        assert(is FunctionModel|ValueModel model = tc.declaration);

        value newScope = if (is FunctionModel model)
            then functionScope(model)
            else getterScope(model);

        try(newScope) {
            that.specifier.visit(this);
        }
    }

    shared actual void visitAnyValue(AnyValue that) {
        "Should have an AttributeDeclaration from the type checker"
        assert (is Tree.AnyAttribute tc = that.get(keys.tcNode));

        "All AnyAttribute nodes should be value declarations"
        assert (is ValueModel model = tc.declarationModel);

        value specifier = that.definition;

        if (exists specifier, !is Specifier specifier) {
            try (getterScope(model)) {
                specifier.visit(this);
            }
        } else {
            "FILEME: The type checker is dumb."
            assert(is Specifier? specifier);

            Ptr<I64Type>? initialValue =
                specifier?.expression?.transform(expressionTransformer);

            scope.allocate(model, initialValue);
        }

        if (model.\iformal || model.\idefault) {
            output.append(vtDispatchGetter(model));

            if (model.\ivariable) {
                output.append(vtDispatchSetter(model));
            }
        }
    }

    shared actual void visitValueSetterDefinition(
            ValueSetterDefinition that) {
        assert(is Tree.AttributeSetterDefinition tc = that.get(keys.tcNode));
        assert(is SetterModel model = tc.declarationModel);
        value parameter = model.parameter;

        try(setterScope(model)) {
            scope.allocate(parameter.model, scope.body.register(ptr(i64), parameter.name));
            that.definition.visit(this);
        }
    }

    shared actual void visitObjectDefinition(ObjectDefinition that) {
        assert(is Tree.ObjectDefinition tc = that.get(keys.tcNode));

        try (constructorScope(tc.anonymousClass)) {
            that.extendedType?.visit(this);
            that.body.visit(this);
        }

        value val = scope.body.call(ptr(i64),
                declarationName(tc.anonymousClass));
        scope.allocate(tc.declarationModel, null);
        scope.body.storeGlobal(declarationName(tc.declarationModel), val);
    }

    shared actual void visitClassDefinition(ClassDefinition that) {
        assert (is Tree.ClassDefinition tc = that.get(keys.tcNode));
        value model = tc.declarationModel;

        try (constructorScope(tc.declarationModel)) {
            for (parameter in CeylonList(model.parameterList.parameters)) {
                scope.allocate(parameter.model, scope.body.register(ptr(i64), parameter.name));
            }

            that.extendedType?.visit(this);
            that.body.visit(this);
        }
    }

    shared actual void visitExtendedType(ExtendedType that) {
        value target = that.target;
        assert (is Tree.InvocationExpression tc = target.get(keys.tcNode));
        assert (is Tree.ExtendedTypeExpression te = tc.primary);

        value arguments = ArrayList<Ptr<I64Type>>();

        for (argument in target.arguments?.argumentList?.children else []) {
            arguments.add(argument.transform(expressionTransformer));
        }

        scope.body.callVoid(initializerName(te.declaration),
            scope.body.register(ptr(i64), frameName), *arguments);
    }

    shared actual void visitLazySpecifier(LazySpecifier that)
        => scope.body.ret(that.expression.transform(expressionTransformer));

    shared actual void visitInterfaceDefinition(InterfaceDefinition that) {
        assert(is Tree.InterfaceDefinition tc = that.get(keys.tcNode));
        try (interfaceScope(tc.declarationModel)) {
            that.body.visit(this);
        }
    }

    shared actual void visitReturn(Return that) {
        Ptr<I64Type> val;
        if (!that.result exists) {
            val = llvmNull;
        } else {
            "Returned expression should have a value"
            assert (is Ptr<I64Type> l = that.result?.transform(expressionTransformer));
            val = l;
        }

        scope.body.ret(val);
    }

    shared actual void visitAnyFunction(AnyFunction that) {
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
            return;
        }

        try (functionScope(tc.declarationModel)) {
            for (parameter in CeylonList(firstParameterList.parameters)) {
                scope.allocate(parameter.model, scope.body.register(ptr(i64),
                            parameter.name));
            }

            that.definition?.visit(this);
        }
    }

    shared actual void visitForFail(ForFail that) {
        value iteratorGetter = termGetMember(that.forClause.iterator.iterated,
                "iterator");
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
            f.block.visit(this);
            breakPosition = scope.body.splitBlock();
        } else {
            breakPosition = loopEnd;
        }

        scope.body.block = loopBody;

        try (scope.LoopContext(loopStart, breakPosition)) {
            that.forClause.block.visit(this);
        }

        scope.body.jump(loopStart);

        scope.body.block = breakPosition;
    }

    shared actual void visitBreak(Break that)
        => scope.breakLoop();

    shared actual void visitContinue(Continue that)
        => scope.continueLoop();

    I1 transformCondition(Condition c) {
        if (is BooleanCondition c) {
            value booleanValue = c.condition.transform(expressionTransformer);
            value trueDeclaration =
                languagePackage.getDirectMember("true", null, false);
            value trueValue = scope.body.call(ptr(i64),
                    getterName(trueDeclaration));
            return scope.body.compareEq(booleanValue, trueValue);
        } else {
            /*TODO: Support exists/nonempty/etc*/
            return I1Lit(0);
        }
    }

    shared actual void visitIfElse(IfElse that) {
        value checkPosition = scope.body.block;
        value trueBlock = scope.body.newBlock();
        value falseBlock = scope.body.newBlock();

        scope.body.block = trueBlock;
        that.ifClause.block.visit(this);
        value trueBlockEnd = if (scope.body.blockTerminated())
            then null
            else scope.body.block;

        scope.body.block = falseBlock;

        if (exists elseClause = that.elseClause) {
            elseClause.visit(this);
        }

        value falseBlockEnd = scope.body.splitBlock();

        if (exists trueBlockEnd, !scope.body.blockTerminated(trueBlockEnd)) {
            scope.body.block = trueBlockEnd;
            scope.body.jump(falseBlockEnd);
        }

        scope.body.block = checkPosition;
        value lastCodition = that.ifClause.conditions.conditions.last;

        for (condition in that.ifClause.conditions.conditions) {
            value conditionValue = transformCondition(condition);

            Label? next = if (lastCodition == condition)
                then trueBlock else null;

            value [nextBlock, _] = scope.body.branch(conditionValue, next,
                    falseBlock);
            scope.body.block = nextBlock;
        }

        scope.body.block = falseBlockEnd;
    }
}
