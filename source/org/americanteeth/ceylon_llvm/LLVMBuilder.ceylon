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
    PackageModel=Package
}

class LLVMBuilder() satisfies Visitor {
    "Nodes to handle by just visiting all children"
    alias StandardNode =>
        ClassBody|ExpressionStatement|Block|CompilationUnit|InvocationStatement;

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
                           @.str``id`` = private alias i64* \
                           bitcast([3 x i64]* @.str``id``.object to i64*)\n\n"
            );
        }

        return result.string;
    }

    "Prefix for all units"
    String preamble = "%.constructor_type = type { i32, void ()* }\n\n";

    "The run() method"
    variable FunctionModel? runSymbol = null;

    "Emitted LLVM for the run() method alias"
    String runSymbolAlias
            => if (exists r = runSymbol)
            then "@__ceylon_run = alias i64*()* @``declarationName(r)``\n"
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

    "Return value from the most recent instruction"
    variable Ptr<I64Type>? lastReturn = null;

    "Stack of declarations we are processing"
    value scopeStack = ArrayList<Scope>();

    "The current scope"
    value scope => scopeStack.last else unitScope;

    "Push a new scope"
    void push(Scope m) => scopeStack.add(m);

    "pop a scope"
    void pop() {
        "We must pop no more scopes than we push"
        assert (exists scope = scopeStack.deleteLast());
        for (result in scope.results) {
            output.append(result);
        }
    }

    shared actual void visitNode(Node that) {
        if (is IgnoredNode that) {
            return;
        }

        if (!is StandardNode that) {
            throw UnsupportedNode(that);
        }

        that.visitChildren(this);
    }

    shared actual void visitAnyValue(AnyValue that) {
        "Should have an AttributeDeclaration from the type checker"
        assert (is Tree.AnyAttribute tc = that.get(keys.tcNode));

        "All AnyAttribute nodes should be value declarations"
        assert (is ValueModel model = tc.declarationModel);

        value specifier = that.definition;

        if (exists specifier, !is Specifier specifier) {
            push(GetterScope(model));
            specifier.visit(this);
            pop();
            return;
        }

        assert (is Specifier? specifier);

        if (exists specifier) {
            specifier.expression.visit(this);
        } else {
            lastReturn = null;
        }

        scope.allocate(model, lastReturn);

        if (!model.captured,
            !model.\ishared,
            !model.container is PackageModel) {
            return;
        }
    }

    shared actual void visitStringLiteral(StringLiteral that) {
        value idNumber = nextStringLiteral++;
        stringLiterals.put(idNumber, that.text);
        lastReturn = scope.body.global(i64, ".str``idNumber``");
    }

    shared actual void visitClassDefinition(ClassDefinition that) {
        assert (is Tree.ClassDefinition tc = that.get(keys.tcNode));
        value model = tc.declarationModel;

        push(ConstructorScope(tc.declarationModel));

        for (parameter in CeylonList(model.parameterList.parameters)) {
            assert (is ValueModel v = parameter.model);
            scope.allocate(v, scope.body.register(ptr(i64), parameter.name));
        }

        that.extendedType?.visit(this);
        that.body.visit(this);

        pop();
    }

    shared actual void visitExtendedType(ExtendedType that) {
        value target = that.target;
        assert (is Tree.InvocationExpression tc = target.get(keys.tcNode));
        assert (is Tree.ExtendedTypeExpression te = tc.primary);

        value arguments = ArrayList<Ptr<I64Type>>();

        if (exists argNode = target.arguments) {
            for (argument in argNode.argumentList.children) {
                argument.visit(this);

                "Arguments must have a value"
                assert (exists l = lastReturn);
                arguments.add(l);
            }
        }

        scope.body.callVoid("``declarationName(te.declaration)``$init",
            scope.body.register(ptr(i64), ".frame"), *arguments);
    }

    shared actual void visitLazySpecifier(LazySpecifier that) {
        that.expression.visit(this);

        "Lazy Specifier expression should have a value"
        assert (exists l = lastReturn);
        scope.body.ret(l);
    }

    shared actual void visitReturn(Return that) {
        Ptr<I64Type> val;
        if (!that.result exists) {
            val = llvmNull;
        } else {
            that.result?.visit(this);

            "Returned expression should have a value"
            assert (exists l = lastReturn);
            val = l;
        }

        scope.body.ret(val);
    }

    shared actual void visitAnyFunction(AnyFunction that) {
        assert (is Tree.AnyMethod tc = that.get(keys.tcNode));

        if (tc.declarationModel.\iformal ||
                    tc.declarationModel.\idefault || tc.declarationModel.\iactual) {
            scope.vtableEntry(tc.declarationModel);
        }

        if (tc.declarationModel.name == "run",
            tc.declarationModel.container is PackageModel) {
            runSymbol = tc.declarationModel;
        }

        "TODO: support multiple parameter lists"
        assert (that.parameterLists.size == 1);

        value firstParameterList = tc.declarationModel.firstParameterList;

        push(FunctionScope(tc.declarationModel));

        for (parameter in CeylonList(firstParameterList.parameters)) {
            assert (is ValueModel v = parameter.model);
            scope.allocate(v, scope.body.register(ptr(i64), parameter.name));
        }

        that.definition?.visit(this);

        pop();
    }

    shared actual void visitInvocation(Invocation that) {
        "We don't support expression callables yet"
        assert (is BaseExpression|QualifiedExpression b = that.invoked);

        "Base expressions should have Base Member or Base Type RH nodes"
        assert (is Tree.MemberOrTypeExpression bt = b.get(keys.tcNode));
        value arguments = ArrayList<Ptr<I64Type>>();

        "We don't support named arguments yet"
        assert (is PositionalArguments pa = that.arguments);

        "We don't support sequence arguments yet"
        assert (!pa.argumentList.sequenceArgument exists);

        if (is QualifiedExpression b) {
            b.receiverExpression.visit(this);
            assert (exists l = lastReturn);
            arguments.add(l);
        } else if (exists f = scope.getFrameFor(bt.declaration)) {
            arguments.add(f);
        }

        for (arg in pa.argumentList.listedArguments) {
            arg.visit(this);

            "Arguments should have a value"
            assert (exists l = lastReturn);
            arguments.add(l);
        }

        lastReturn =
            scope.body.call(ptr(i64), declarationName(bt.declaration),
                *arguments);
    }

    shared actual void visitBaseExpression(BaseExpression that) {
        assert (is Tree.BaseMemberExpression tb = that.get(keys.tcNode));
        assert (is ValueModel declaration = tb.declaration);
        lastReturn = scope.access(declaration);
    }

    shared actual void visitQualifiedExpression(QualifiedExpression that) {
        "TODO: Support fancy member operators"
        assert (that.memberOperator is MemberOperator);

        assert (is Tree.QualifiedMemberOrTypeExpression tc =
                that.get(keys.tcNode));

        value getterName = "``declarationName(tc.declaration)``$get";

        that.receiverExpression.visit(this);
        assert (exists target = lastReturn);

        lastReturn = scope.body.call(ptr(i64), getterName, target);
    }
}
