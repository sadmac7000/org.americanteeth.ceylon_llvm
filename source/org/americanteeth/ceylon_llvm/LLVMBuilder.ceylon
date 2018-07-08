import ceylon.ast.core {
    ...
}

import ceylon.interop.java {
    CeylonList
}

import ceylon.collection {
    ArrayList
}

import org.eclipse.ceylon.compiler.typechecker.tree {
    Tree
}

import org.eclipse.ceylon.model.typechecker.model {
    DeclarationModel=Declaration,
    FunctionModel=Function,
    FunctionOrValueModel=FunctionOrValue,
    ValueModel=Value,
    SetterModel=Setter,
    PackageModel=Package
}

class LLVMBuilder(String module_name,
                  String? target,
                  shared actual PackageModel languagePackage)
        satisfies Visitor&CodeWriter&Destroyable {
    "The LLVM Module we will build our code in"
    shared actual LLVMModule llvmModule = LLVMModule.withName(module_name);

    if (exists target) {
        llvmModule.target = target;
    }

    string => llvmModule.string;

    "Write an LLVM bitcode file"
    shared void writeBitcodeFile(String path)
        => llvmModule.writeBitcodeFile(path);

    shared actual void destroy(Throwable? error) => llvmModule.destroy(error);

    "The run() method"
    variable FunctionModel? runSymbol_ = null;

    "Accessor for runSymbol_"
    FunctionModel? runSymbol => runSymbol_;

    "Writer for runSymbol_"
    assign runSymbol {
        "Units should only have one run symbol."
        assert(! runSymbol_ exists);

        runSymbol_ = runSymbol;

        //llvmModule.addAlias("__ceylon_run", declarationName(runSymbol));
    }
    /*"Emitted LLVM for the run() method alias"
    String runSymbolAlias
            => if (exists r = runSymbol)
            then "@__ceylon_run = alias i64*(),i64*()* @``declarationName(r)``\n"
            else "";*/

    "The code we are outputting"
    value output = LLVMUnit();

    "Top-level scope of the compilation unit"
    shared Scope unitScope = UnitScope(llvmModule);

    "Stack of declarations we are processing"
    value scopeStack = ArrayList<Scope>();

    "The current scope"
    shared actual Scope scope => scopeStack.last else unitScope;

    "Push a new scope"
    shared actual T push<T>(T m) given T satisfies Scope {
        scopeStack.add(m);
        return m;
    }

    "pop a scope"
    shared actual void pop(Scope check) {
        "We must pop no more scopes than we push"
        assert (exists scope = scopeStack.deleteLast());

        "We did not pop the scope we expected"
        assert(scope == check);

        for (result in scope.results) {
            output.append(result);
        }
    }

    variable ExpressionTransformer? expressionTransformer_ = null;

    "Our expression transformer"
    shared actual ExpressionTransformer expressionTransformer
        => expressionTransformer_ else (expressionTransformer_ =
            ExpressionTransformer(this));

    shared actual void visitNode(Node that) {
        throw UnsupportedNode(that);
    }

    shared actual void visitExpressionStatement(ExpressionStatement that)
        => that.transformChildren(expressionTransformer);

    shared actual void visitInvocationStatement(InvocationStatement that)
        => that.transformChildren(expressionTransformer);

    shared actual void visitCompilationUnit(CompilationUnit that)
        => that.visitChildren(this);

    shared actual void visitClassBody(ClassBody that)
        => that.visitChildren(this);

    shared actual void visitInterfaceBody(InterfaceBody that)
        => that.visitChildren(this);

    shared actual void visitBlock(Block that)
        => that.visitChildren(this);

    shared actual void visitImport(Import that) {}
    shared actual void visitModuleCompilationUnit(ModuleCompilationUnit that) {}
    shared actual void visitPackageCompilationUnit(PackageCompilationUnit that) {}
    shared actual void visitAnnotations(Annotations that) {}
    shared actual void visitTypeAliasDefinition(TypeAliasDefinition that) {}

    shared actual void visitValueSpecification(ValueSpecification that) {
        assert(is Tree.SpecifierStatement tc = that.get(keys.tcNode));

        ValueModel model;

        if (that.qualifier exists ) {
            assert(is Tree.QualifiedMemberExpression qme =
                    tc.baseMemberExpression);
            assert(is ValueModel mod = qme.declaration);
            model = mod;
        } else {
            assert(is ValueModel mod = tc.declaration);
            model = mod;
        }

        value setting =
            that.specifier.expression.transform(expressionTransformer);

        if (scope.owns(model)) {
            scope.allocate(model, setting);
        } else {
            scope.store(model, setting);
        }
    }

    shared actual void visitLazySpecification(LazySpecification that) {
        assert(is Tree.SpecifierStatement|Tree.MethodArgument tc = that.get(keys.tcNode));

        value model = if (is Tree.SpecifierStatement tc)
            then tc.declaration
            else tc.declarationModel;

        assert(is FunctionModel|ValueModel model);

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

        if (! baremetalSupports(model)) {
            return;
        }

        value specifier = that.definition;

        if (exists specifier, !is Specifier specifier) {
            try (getterScope(model)) {
                specifier.visit(this);
            }
        } else {
            "FILEME: The type checker is dumb."
            assert(is Specifier? specifier);

            Ptr<I64Type>? initialValue =
                specifier?.expression?.transform(expressionTransformer) else
                (if (model.captured) then null
                else undef(ptr(i64)));

            scope.allocate(model, initialValue);
        }

        if (model.\iformal || model.\idefault) {
            output.append(vtDispatchGetter(llvmModule, model));

            if (model.\ivariable) {
                output.append(vtDispatchSetter(llvmModule, model));
            }
        }
    }

    shared actual void visitValueSetterDefinition(
            ValueSetterDefinition that) {
        assert(is Tree.AttributeSetterDefinition tc = that.get(keys.tcNode));
        assert(is SetterModel model = tc.declarationModel);

        if (! baremetalSupports(model)) {
            return;
        }

        value parameter = model.parameter;

        try(setterScope(model)) {
            scope.allocate(parameter.model, scope.body.register(ptr(i64), parameter.name));
            that.definition.visit(this);
        }
    }

    shared actual void visitObjectDefinition(ObjectDefinition that) {
        assert(is Tree.ObjectDefinition tc = that.get(keys.tcNode));

        if (! baremetalSupports(tc.declarationModel)) {
            return;
        }

        try (constructorScope(tc.anonymousClass)) {
            that.extendedType?.visit(this);
            that.body.visit(this);
        }

        value val = scope.callI64(declarationName(tc.anonymousClass),
                *{scope.getContextFor(tc.anonymousClass)}.coalesced);
        scope.allocate(tc.declarationModel, null);
        scope.body.storeGlobal(declarationName(tc.declarationModel), val);
    }

    shared actual void visitClassDefinition(ClassDefinition that) {
        assert (is Tree.ClassDefinition tc = that.get(keys.tcNode));
        value model = tc.declarationModel;

        if (! baremetalSupports(model)) {
            return;
        }

        if (! model.parameterList exists) {
            return; /* TODO: Support advanced constructors */
        }

        try (constructorScope(tc.declarationModel)) {
            if (exists parameterList = model.parameterList) {
                for (parameter in CeylonList(parameterList.parameters)) {
                    scope.allocate(parameter.model,
                            scope.body.register(ptr(i64), parameter.name));
                }
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

        if (! baremetalSupports(tc.declarationModel)) {
            return;
        }

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

        if (! baremetalSupports(tc.declarationModel)) {
            return;
        }

        if (tc.declarationModel.name == "run",
            tc.declarationModel.container is PackageModel) {
            runSymbol = tc.declarationModel;
        }

        /* TODO: Support multiple parameter lists */
        if (that.parameterLists.size > 1) {
            try(functionScope(tc.declarationModel)) {
                scope.body.ret(llvmNull);
            }
            return;
        }

        value firstParameterList = tc.declarationModel.firstParameterList;

        if (tc.declarationModel.\iformal || tc.declarationModel.\idefault) {
            output.append(vtDispatchFunction(llvmModule, tc.declarationModel));
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
        value iteratedNode = that.forClause.iterator.iterated;
        value iteration = iterationForNode(iteratedNode);
        value finishedVal = getLanguageValue("finished");

        value loopStart = scope.body.splitBlock();

        value nextValue = iteration.getNext();

        value comparison = scope.body.compareEq(nextValue, finishedVal);
        let ([loopEnd, loopBody] = scope.body.branch(comparison));

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
            assignPattern(that.forClause.iterator.pattern, nextValue,
                    iteration.elementType.declaration);
            that.forClause.block.visit(this);
        }

        scope.body.jump(loopStart);

        scope.body.block = breakPosition;
    }

    shared actual void visitBreak(Break that)
        => scope.breakLoop();

    shared actual void visitContinue(Continue that)
        => scope.continueLoop();

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
            elseClause.child.visit(this);
        }

        value falseBlockEnd = scope.body.splitBlock();

        if (exists trueBlockEnd, !scope.body.blockTerminated(trueBlockEnd)) {
            scope.body.block = trueBlockEnd;
            scope.body.jump(falseBlockEnd);
        }

        scope.body.block = checkPosition;

        package.transformConditions(that.ifClause.conditions, scope,
                languagePackage, expressionTransformer, trueBlock, falseBlock);

        scope.body.block = falseBlockEnd;
    }

    shared actual void visitThrow(Throw that) {
        /* TODO: Support exception handling */
        scope.body.callVoid("abort");
        scope.body.unreachable();
    }

    shared actual void visitAssertion(Assertion that) {
        value trueBlock = scope.body.newBlock();
        value falseBlock = scope.body.newBlock();

        package.transformConditions(that.conditions, scope,
                languagePackage, expressionTransformer, trueBlock, falseBlock);

        scope.body.block = falseBlock;

        /* TODO: Throw an exception when we have those */
        scope.body.callVoid("abort");
        scope.body.unreachable();

        scope.body.block = trueBlock;
    }

    shared actual void visitWhile(While that) {
        value trueBlock = scope.body.newBlock();
        value falseBlock = scope.body.newBlock();
        value loopStart = scope.body.splitBlock();

        package.transformConditions(that.conditions, scope,
                languagePackage, expressionTransformer, trueBlock, falseBlock);

        scope.body.block = trueBlock;
        try (scope.LoopContext(loopStart, falseBlock)) {
            that.block.visit(this);
        }
        scope.body.jump(loopStart);

        scope.body.block = falseBlock;
    }

    shared actual void visitSwitchCaseElse(SwitchCaseElse that) {
        processSwitch(that, this);
    }

    void assignPattern(Pattern pattern, Ptr<I64Type> val,
            DeclarationModel d) {
        if (is VariablePattern pattern) {
            assert(is FunctionOrValueModel mod =
                    termGetDeclaration(pattern.\ivariable));
            scope.allocate(mod, val);
        } else if (is EntryPattern pattern) {
            value keyDeclaration = d.getMember("key", null, false);
            value itemDeclaration = d.getMember("item", null, false);
            value key = scope.callI64(getterName(keyDeclaration), val);
            value item = scope.callI64(getterName(itemDeclaration), val);
            assignPattern(pattern.key, key, d.getMember("key", null, false));
            assignPattern(pattern.item, item, d.getMember("item", null, false));
        } else {
            variable value index = 0;
            for(element in pattern.elementPatterns)  {
                //value pos = index++;
                assert(is FunctionModel getModel = d.getMember("get", null, false));
                // TODO: That llvmNull becomes an integer literal == pos when we
                // have integers.
                value next = scope.callI64(declarationName(getModel), val, llvmNull);
                assignPattern(element, next, getModel.type.declaration);
            }

            value variadic = pattern.variadicElementPattern;
            if (! exists variadic) {
                return;
            }

            value remainder = scope.callI64(declarationName(d.getMember("spanFrom", null, false)),
                    I64Lit(index));
            assert(is FunctionOrValueModel mod = termGetDeclaration(variadic));
            scope.allocate(mod, remainder);
        }
    }

    shared actual void visitDestructure(Destructure that)
        => assignPattern(that.pattern,
                that.specifier.expression.transform(expressionTransformer),
                termGetType(that.specifier.expression).declaration);

    shared actual void visitPatternList(PatternList that) {
        for (pattern in that.patterns) {
            value result =
                pattern.specifier.expression.transform(expressionTransformer);
            value dec = termGetType(pattern.specifier.expression).declaration;
            assignPattern(pattern.pattern, result, dec);
        }
    }

    /* TODO: Constructors. */
    shared actual void visitCallableConstructorDefinition(
            CallableConstructorDefinition that) {}
}
