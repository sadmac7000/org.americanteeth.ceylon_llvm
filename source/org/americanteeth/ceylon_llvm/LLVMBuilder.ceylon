import ceylon.ast.core {
    ...
}

import ceylon.interop.java {
    CeylonList
}

import ceylon.collection {
    ArrayList,
    HashMap,
    HashSet
}

import com.redhat.ceylon.compiler.typechecker.tree {
    Tree
}

import com.redhat.ceylon.model.typechecker.model {
    FunctionModel = Function,
    ValueModel = Value,
    DeclarationModel = Declaration,
    ClassModel = Class,
    PackageModel = Package
}

class LLVMBuilder() satisfies Visitor {
    "Nodes to handle by just visiting all children"
    alias StandardNode => ClassBody|ExpressionStatement|Block|CompilationUnit|InvocationStatement;

    "Nodes to ignore completely"
    alias IgnoredNode => Import|ModuleCompilationUnit|PackageCompilationUnit|Annotations;

    "The next string literal ID available"
    variable value nextStringLiteral = 0;

    "A table of all string literals"
    value stringLiterals = HashMap<Integer,String>();

    "LLVM text for the string table"
    String stringTable {
        value result = StringBuilder();

        for (id -> raw in stringLiterals) {
            value [str, sz] = processEscapes(raw);
            result.append("@.str``id``.data = private unnamed_addr constant \
                           [``sz`` x i8] c\"``str``\"
                           @.str``id``.object = private unnamed_addr constant \
                           [3 x i64] [i64 0, i64 ``sz``, \
                           i64 ptrtoint([``sz`` x i8]* @.str``id``.data to i64)]
                           @.str``id`` = private alias i64* \
                           bitcast([3 x i64]* @.str``id``.object to i64*)\n\n");
        }

        return result.string;
    }

    "Declarations we will be outputting"
    value declaredItems = HashSet<DeclarationModel>();

    "Declarations we will need to link externally"
    value usedItems = HashSet<DeclarationModel>();

    "Predeclaration text"
    String predeclarations {
        value models = usedItems ~ declaredItems;
        value result = StringBuilder();

        for (model in models) {
            if (is FunctionModel|ClassModel model) {
                value arguments = StringBuilder();
                variable Boolean first = true;

                if (!(model of DeclarationModel).toplevel) {
                    arguments.append("i64* %.context");
                    first = false;
                }

                for (param in CeylonList(model.firstParameterList.parameters)) {
                    if (! first) {
                        arguments.append(", ");
                    }
                    first = false;
                    arguments.append("i64*");
                }

                result.append("declare i64* @");
                result.append(declarationName(model));
                result.append("(``arguments``)\n");

                if (is ClassModel model) {
                    result.append("declare void @");
                    result.append(declarationName(model));

                    if (arguments.empty) {
                        result.append("$init(i64* %.frame)\n");
                    } else {
                        result.append("$init(i64* %.frame, ``arguments``)\n");
                    }

                    result.append("declare i64 @");
                    result.append(declarationName(model));
                    result.append("$size()\n");
                }
            } else if (is ValueModel model) {
                result.append("declare i64* @");
                result.append(declarationName(model));
                result.append("$get(");

                if (!model.toplevel) {
                    result.append("i64* %.context");
                }

                result.append(")\n");
            }
        }

        result.append("\n");
        return result.string;
    }

    "Prefix for all units"
    String preamble = "declare i64* @malloc(i64)
                       define private i64 @cMS4yLjA.ceylon.language.$Basic$size() {
                           ret i64 2;
                       }\n\n";

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
    value output = StringBuilder();
    string => preamble + stringTable + predeclarations + output.string +
        unitScope.string + runSymbolAlias;

    "Return value from the most recent instruction"
    variable String? lastReturn = null;

    "Stack of declarations we are processing"
    value scopeStack = ArrayList<Scope>();

    "The current scope"
    value scope => scopeStack.last else unitScope;

    "Push a new scope"
    void push(Scope m) => scopeStack.add(m);

    "pop a scope"
    void pop() {
        "We must pop no more scopes than we push"
        assert(exists scope = scopeStack.deleteLast());
        output.append(scope.string);
        usedItems.addAll(scope.usedItems);
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
        assert(is Tree.AnyAttribute tc = that.get(keys.tcNode));

        "All AnyAttribute nodes should be value declarations"
        assert(is ValueModel model = tc.declarationModel);

        value specifier = that.definition;

        if (exists specifier, ! is Specifier specifier) {
            push(GetterScope(model));
            specifier.visit(this);
            pop();
            declaredItems.add(model);
            return;
        }

        assert(is Specifier? specifier);

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

        declaredItems.add(model);

        if (exists g = scope.getterFor(model)) {
            push(g);
            pop();
        }

        if (!model.\ivariable) {
            return;
        }

        /* We'll have an `assign` statement later that'll fill this in */
        if (model.setter exists) {
            return;
        }

        push(scope.setterFor(model));
        pop();
    }

    shared actual void visitStringLiteral(StringLiteral that) {
        value idNumber = nextStringLiteral++;
        stringLiterals.put(idNumber, that.text);
        lastReturn = "@.str``idNumber``";
    }

    shared actual void visitClassDefinition(ClassDefinition that) {
        assert(is Tree.ClassDefinition tc = that.get(keys.tcNode));
        value model = tc.declarationModel;
        declaredItems.add(model);

        push(ConstructorScope(tc.declarationModel));

        for (parameter in CeylonList(model.parameterList.parameters)) {
            assert(is ValueModel v = parameter.model);
            scope.allocate(v, "%``parameter.name``");

            if (exists g = scope.getterFor(v)) {
                declaredItems.add(v);
                push(g);
                pop();
            }
        }

        that.extendedType?.visit(this);
        that.body.visit(this);

        pop();
    }

    shared actual void visitExtendedType(ExtendedType that) {
        value target = that.target;
        assert(is Tree.InvocationExpression tc = target.get(keys.tcNode));
        assert(is Tree.ExtendedTypeExpression te = tc.primary);

        value instruction = StringBuilder();

        instruction.append("call void \
                            @``declarationName(te.declaration)``$init(");
        instruction.append("i64* %.frame");
        usedItems.add(te.declaration);

        if (exists arguments = target.arguments) {

            for (argument in arguments.argumentList.children) {
                argument.visit(this);

                "Arguments must have a value"
                assert(exists l = lastReturn);
                instruction.append(", i64* ``l``");
            }
        }

        instruction.append(")");
        scope.addInstruction(instruction.string);
    }

    shared actual void visitLazySpecifier(LazySpecifier that) {
        that.expression.visit(this);

        "Lazy Specifier expression should have a value"
        assert(exists l = lastReturn);
        scope.addInstruction("ret i64* ``l``");
    }

    shared actual void visitReturn(Return that) {
        String val;
        if (! that.result exists) {
            val = "null";
        } else {
            that.result?.visit(this);

            "Returned expression should have a value"
            assert(exists l = lastReturn);
            val = l;
        }

        scope.addInstruction("ret i64* ``val``");
    }

    shared actual void visitAnyFunction(AnyFunction that) {
        if (is FunctionDeclaration that) {
            return;
        }

        assert(is Tree.AnyMethod tc = that.get(keys.tcNode));

        if (tc.declarationModel.name == "run",
            tc.declarationModel.container is PackageModel) {
            runSymbol = tc.declarationModel;
        }

        "TODO: support multiple parameter lists"
        assert(that.parameterLists.size == 1);

        value firstParameterList = tc.declarationModel.firstParameterList;

        declaredItems.add(tc.declarationModel);
        push(FunctionScope(tc.declarationModel));

        for (parameter in CeylonList(firstParameterList.parameters)) {
            assert(is ValueModel v = parameter.model);
            scope.allocate(v, "%``parameter.name``");

            if (exists g = scope.getterFor(v)) {
                declaredItems.add(v);
                push(g);
                pop();
            }
        }

        that.definition?.visit(this);
        pop();
    }

    shared actual void visitInvocation(Invocation that) {
        "We don't support expression callables yet"
        assert(is BaseExpression|QualifiedExpression b = that.invoked);

        "Base expressions should have Base Member or Base Type RH nodes"
        assert(is Tree.MemberOrTypeExpression bt = b.get(keys.tcNode));
        value instruction = StringBuilder();

        instruction.append("call i64* @");
        instruction.append(declarationName(bt.declaration) + "(");
        usedItems.add(bt.declaration);

        "We don't support named arguments yet"
        assert(is PositionalArguments pa = that.arguments);

        "We don't support sequence arguments yet"
        assert(! pa.argumentList.sequenceArgument exists);

        variable Boolean first = false;

        if (is QualifiedExpression b) {
            b.receiverExpression.visit(this);
            assert(exists l = lastReturn);
            instruction.append("i64* ``l``");
        } else if (exists f = scope.getFrameFor(bt.declaration)) {
            instruction.append("i64* ``f``");
        } else {
            first = true;
        }

        for (arg in pa.argumentList.listedArguments) {
            arg.visit(this);

            if (! first) {
                instruction.append(", ");
            }

            "Arguments should have a value"
            assert(exists l = lastReturn);
            instruction.append("i64* ``l``");

            first = false;
        }

        instruction.append(")");
        lastReturn = scope.addValueInstruction(instruction.string);
    }

    shared actual void visitBaseExpression(BaseExpression that) {
        assert(is Tree.BaseMemberExpression tb = that.get(keys.tcNode));
        assert(is ValueModel declaration = tb.declaration);
        lastReturn = scope.access(declaration);
    }

    shared actual void visitQualifiedExpression(QualifiedExpression that) {
        "TODO: Support fancy member operators"
        assert(that.memberOperator is MemberOperator);

        assert(is Tree.QualifiedMemberOrTypeExpression tc =
                that.get(keys.tcNode));

        value getterName = "``declarationName(tc.declaration)``$get";

        that.receiverExpression.visit(this);
        assert(exists target = lastReturn);

        lastReturn = scope.addValueInstruction(
                "call i64* @``getterName``(i64* ``target``)");
    }
}
