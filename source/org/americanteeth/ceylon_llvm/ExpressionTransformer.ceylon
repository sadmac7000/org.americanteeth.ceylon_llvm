import ceylon.ast.core {
    ...
}

import ceylon.collection {
    ArrayList,
    HashMap
}

import ceylon.interop.java {
    CeylonList
}

import com.redhat.ceylon.compiler.typechecker.tree {
    Tree
}

import com.redhat.ceylon.model.typechecker.model {
    FunctionOrValueModel=FunctionOrValue,
    FunctionalModel=Functional,
    PackageModel=Package,
    TypeModel=Type,
    TypeDeclaration,
    ValueModel=Value,
    ParameterModel=Parameter
}

class ExpressionTransformer(LLVMBuilder builder)
        satisfies WideningTransformer<Ptr<I64Type>>&CodeWriter {

    "The next string literal ID available"
    variable value nextStringLiteral = 0;

    "A table of all string literals"
    value stringLiterals = HashMap<Integer,String>();

    shared actual Scope scope => builder.scope;
    shared actual ExpressionTransformer expressionTransformer => this;
    shared actual T push<T>(T m) given T satisfies Scope => builder.push(m);
    shared actual void pop(Scope check) => builder.pop(check);
    shared actual PackageModel languagePackage => builder.languagePackage;

    "Check whether a value is ceylonically true. I.e. convert a Ceylon Boolean
     to an LLVM I1."
     I1 checkTrue(Ptr<I64Type> val) {
         value trueValue = getLanguageValue("true");
         return scope.body.compareEq(val, trueValue);
     }

    "LLVM text for the string table"
    shared String stringTable() {
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

    Boolean isSuper(Node that) {
        if (is Super that) {
            return true;
        } else if (is OfOperation that) {
            return isSuper(that.operand);
        } else if (is GroupedExpression that) {
            return isSuper(that.innerExpression);
        } else {
            return false;
        }
    }

    shared actual Nothing transformNode(Node that) {
        throw UnsupportedNode(that);
    }

    shared actual Ptr<I64Type> transformStringLiteral(StringLiteral that) {
        value idNumber = nextStringLiteral++;
        stringLiterals.put(idNumber, that.text);
        return scope.body.global(i64, ".str``idNumber``");
    }

    shared actual Ptr<I64Type> transformInvocation(Invocation that) {
        value invoked = that.invoked;
        value declaration = termGetDeclaration(invoked);

        if (! is FunctionalModel declaration) {
            value args = that.arguments.transform(this);
            value callable = that.invoked.transform(this);
            return scope.callI64("__ceylon_invoke_callable", callable, args);
        }

        value arguments = ArrayList<Ptr<I64Type>>();

        value sup = if (is QualifiedExpression invoked,
                isSuper(invoked.receiverExpression))
            then true else false;

        if (is QualifiedExpression invoked,
            ! invoked.receiverExpression is Package|This,
            ! isSuper(invoked.receiverExpression)) {
            arguments.add(invoked.receiverExpression.transform(this));
        } else if (exists f = scope.getContextFor(declaration, sup)) {
            arguments.add(f);
        }

        value functionName = if (is QualifiedExpression invoked,
                isSuper(invoked.receiverExpression))
            then dispatchName(declaration)
            else declarationName(declaration);

        value parameterList =
            ArrayList{*CeylonList(declaration.firstParameterList.parameters)};

        value sequencedParameter = if (exists p = parameterList.last, p.sequenced)
            then parameterList.deleteLast()
            else null;

        value args = that.arguments;

        if (is PositionalArguments args) {
            value list = args.argumentList;
            value argValues = list.listedArguments.collect(
                    (x) => x.transform(this));
            value serialArguments = argValues.spanTo(parameterList.size);
            value leftOverArguments = argValues.spanFrom(parameterList.size);
            value leftOverParameters =
                parameterList.spanFrom(serialArguments.size);

            "We should only be left with unused arguments
             OR unbound parameters."
            assert(leftOverParameters.empty || leftOverArguments.empty);

            for (arg in serialArguments) {
                arguments.add(arg);
            }

            if (list.sequenceArgument exists,
                    !leftOverParameters.empty) {
                value [spreadArg, type] = getSpreadArg(list);
                value finishedObject = getLanguageValue("finished");
                value iteration = Iteration(spreadArg, type);
                value defaulted = scope.body.loadGlobal(ptr(i64),
                        "__ceylon_default_poison");

                for (parameter in leftOverParameters) {
                    value nextArg = iteration.getNext();
                    value checkFinished = scope.body.compareEq(nextArg,
                            finishedObject);
                    arguments.add(scope.body.select(checkFinished, ptr(i64),
                                defaulted, nextArg));
                }

                if (list.sequenceArgument exists) {
                    value spanFrom = type.declaration.getMember("spanFrom", null,
                            false);

                    arguments.add(scope.callI64(declarationName(spanFrom),
                                spreadArg, I64Lit(leftOverParameters.size)));
                }
            } else if (!leftOverParameters.empty) {
                value defaulted = scope.body.loadGlobal(ptr(i64),
                        "__ceylon_default_poison");
                for (parameter in leftOverParameters) {
                    arguments.add(defaulted);
                }
            } else if (!leftOverArguments.empty) {
                "Remaining arguments should go to a sequenced parameter."
                assert(exists sequencedParameter);

                arguments.add(makeTuple(leftOverArguments,
                            getSpreadArg(list)[0]));
            } else if (exists sequencedParameter,
                    list.sequenceArgument exists) {
                arguments.add(getSpreadArg(list)[0]);
            }
        } else {
            value iterableArgument =
                if (args.iterableArgument.sequenceArgument exists ||
                        !args.iterableArgument.listedArguments.empty)
                then args.iterableArgument.transform(this)
                else null;

            /* Sometimes we get a named argument here. No idea why. */
            Tree.SequencedArgument? iterableTc =
                    if (is Tree.SequencedArgument t =
                            args.iterableArgument.get(keys.tcNode))
                    then t
                    else null;

            value iterableDecl = iterableTc?.parameter;

            value argumentValues = HashMap<ParameterModel,Ptr<I64Type>>();

            if (exists iterableArgument) {
                assert(exists iterableDecl);
                argumentValues[iterableDecl] = iterableArgument;
            }

            for (namedArgument in args.namedArguments) {
                assert(is Tree.NamedArgument tc = namedArgument.get(keys.tcNode));
                argumentValues[tc.parameter] = namedArgument.transform(this);
            }

            variable Ptr<I64Type>? defaulted_ = null;
            value defaulted => defaulted_ = defaulted_ else
                scope.body.loadGlobal(ptr(i64), "__ceylon_default_poison");

            for (p in parameterList) {
                if (exists val = argumentValues[p]) {
                    arguments.add(val);
                } else {
                    arguments.add(defaulted);
                }
            }
        }

        return scope.callI64(functionName, *arguments);
    }

    shared actual Ptr<I64Type> transformAnonymousArgument(
            AnonymousArgument that)
        => that.expression.transform(this);

    /* Normal and lazy specifiers behave the same way in named arguments. The
     * other back ends seem to agree with this behavior. The spec has no
     * opinion I can find.
     */
    shared actual Ptr<I64Type> transformSpecifiedArgument(
            SpecifiedArgument that)
        => that.specification.specifier.expression.transform(this);

    shared actual Ptr<I64Type> transformBaseExpression(BaseExpression that)
        => scope.load(termGetDeclaration(that));

    shared actual Ptr<I64Type> transformQualifiedExpression(QualifiedExpression that) {
        value receiver = if (isSuper(that.receiverExpression))
            then scope.getContextFor(termGetDeclaration(that), true)
            else that.receiverExpression.transform(this);

        assert(exists receiver);

        function getResult()
            => scope.callI64(getterName(termGetDeclaration(that)), receiver);

        if (that.memberOperator is MemberOperator) {
            return getResult();
        }

        "TODO: Support spread member operators"
        assert(that.memberOperator is SafeMemberOperator);

        scope.body.mark(that, llvmNull);
        value comparison = scope.body.compareNE(receiver, llvmNull);
        value [trueBlock, falseBlock] = scope.body.branch(comparison);

        scope.body.block = trueBlock;
        scope.body.mark(that, getResult());
        scope.body.jump(falseBlock);

        scope.body.block = falseBlock;
        assert(exists ret = scope.body.getMarked(ptr(i64), that));
        return ret;
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

    shared actual Ptr<I64Type> transformNotOperation(NotOperation that) {
        value trueObject = getLanguageValue("true");
        value falseObject = getLanguageValue("false");
        value expression = that.operand.transform(this);
        value test = scope.body.compareEq(expression, trueObject);

        return scope.body.select(test, ptr(i64), falseObject, trueObject);
    }

    /* TODO: Implement this once we have callable support */
    shared actual Ptr<I64Type> transformFunctionExpression(
            FunctionExpression that) => llvmNull;

    /* TODO: Design and implement integer literals */
    shared actual Ptr<I64Type> transformIntegerLiteral(
            IntegerLiteral that) => llvmNull;

    "Assign a new value to an element represented by a Term."
    void assignTerm(Node term, Ptr<I64Type> toAssign) {
        "We can only assign to base expressions, qualified expressions, or
         Element/Subrange expressions"
        assert(
            is BaseExpression|QualifiedExpression|ElementOrSubrangeExpression
                term);

        if (is ElementOrSubrangeExpression term) {
            value type = termGetType(term.primary);
            assert(is TypeDeclaration icMutator =
                languagePackage.getDirectMember("IndexedCorrespondenceMutator",
                        null, false));
            value callName = if (type.getSupertype(icMutator) exists)
                then "set"
                else "put";

            scope.callI64(termGetMemberName(term.primary, callName),
                    term.subscript.transform(this), toAssign);
            return;
        }

        assert(is FunctionOrValueModel declaration = termGetDeclaration(term));

        if (is BaseExpression term) {
            scope.store(declaration, toAssign);
        } else {
            scope.callI64(setterName(declaration),
                    term.receiverExpression.transform(this),
                    toAssign);
        }
    }

    shared actual Ptr<I64Type> transformAssignmentOperation(AssignmentOperation that) {
        value transformedRight = that.rightOperand.transform(this);

        variable Ptr<I64Type>? transformedLeft_ = null;
        value transformedLeft => transformedLeft_ = transformedLeft_ else
            that.leftOperand.transform(this);

        Ptr<I64Type> op(String name)
            => scope.callI64(termGetMemberName(that.leftOperand, name),
                    transformedLeft, transformedRight);

        value toAssign = switch(that)
            case (is AssignOperation) transformedRight
            case (is AddAssignmentOperation) op("plus")
            case (is SubtractAssignmentOperation) op("minus")
            case (is MultiplyAssignmentOperation) op("times")
            case (is DivideAssignmentOperation) op("divided")
            case (is RemainderAssignmentOperation) op("remainder")
            case (is UnionAssignmentOperation) op("union")
            case (is IntersectAssignmentOperation) op("intersection")
            case (is ComplementAssignmentOperation) op("complement")
            else null;

        "TODO: Support logical assignment operators"
        assert(exists toAssign);

        assignTerm(that.leftOperand, toAssign);

        return toAssign;
    }

    shared actual Ptr<I64Type> transformIfElseExpression(IfElseExpression that) {
        value checkPosition = scope.body.block;
        value trueBlock = scope.body.newBlock();
        value falseBlock = scope.body.newBlock();

        scope.body.block = trueBlock;
        value trueValue = that.thenExpression.transform(this);
        value trueBlockLast = scope.body.block;
        scope.body.mark(that, trueValue);

        scope.body.block = falseBlock;
        value falseValue = that.elseExpression.transform(this);
        value falseBlockEnd = scope.body.splitBlock();
        scope.body.mark(that, falseValue);

        scope.body.block = trueBlockLast;
        scope.body.jump(falseBlockEnd);

        scope.body.block = checkPosition;
        package.transformConditions(that.conditions, scope,
                builder.languagePackage, this, trueBlock, falseBlock);

        scope.body.block = falseBlockEnd;
        assert(exists ret = scope.body.getMarked(ptr(i64), that));
        return ret;
    }

    shared actual Ptr<I64Type> transformIdenticalOperation(IdenticalOperation that) {
        value trueValue = getLanguageValue("true");
        value falseValue = getLanguageValue("false");

        value left = that.leftOperand.transform(this);
        value right = that.rightOperand.transform(this);

        value compare = scope.body.compareEq(left, right);
        return scope.body.select(compare, ptr(i64), trueValue, falseValue);
    }

    shared actual Ptr<I64Type> transformBinaryOperation(
            BinaryOperation that) {
        value left = that.leftOperand.transform(this);
        value right = that.leftOperand.transform(this);

        Ptr<I64Type> op(String name)
            => scope.callI64(termGetMemberName(that.leftOperand, name),
                    left, right);

        Ptr<I64Type> opR(String name)
            => scope.callI64(termGetMemberName(that.rightOperand, name),
                    right, left);

        Ptr<I64Type> opS(String name)
            => scope.callI64(declarationName(getLanguageDeclaration(name)),
                    left, right);


        "These operations are handled elsewhere."
        assert(! is
                AssignmentOperation|LogicalOperation|ThenOperation|
                ElseOperation|NotEqualOperation|IdenticalOperation|
                ComparisonOperation that);

        return switch(that)
            case (is SumOperation) op("plus")
            case (is DifferenceOperation) op("minus")
            case (is ProductOperation) op("times")
            case (is QuotientOperation) op("divided")
            case (is RemainderOperation) op("remainder")
            case (is ExponentiationOperation) op("power")
            case (is UnionOperation) op("union")
            case (is IntersectionOperation) op("intersection")
            case (is ComplementOperation) op("complement")
            case (is ScaleOperation) opR("scale")
            case (is InOperation) opR("contains")
            case (is CompareOperation) op("compare")
            case (is EqualOperation) op("equals")
            case (is EntryOperation) opS("Entry")
            case (is SpanOperation) opS("span")
            case (is MeasureOperation) opS("measure");
    }

    shared actual Ptr<I64Type> transformNotEqualOperation(NotEqualOperation that) {
        value leftOperand = that.leftOperand.transform(this);
        value rightOperand = that.leftOperand.transform(this);
        value equalsFunction = termGetMember(that.leftOperand, "equals");
        value eq = scope.callI64(declarationName(equalsFunction),
                leftOperand, rightOperand);
        value trueValue = getLanguageValue("true");
        value falseValue = getLanguageValue("false");
        value bool = scope.body.compareEq(eq, trueValue);
        return scope.body.select(bool, ptr(i64), falseValue, trueValue);
    }

    shared actual Ptr<I64Type> transformGroupedExpression(
            GroupedExpression that)
        => that.innerExpression.transform(this);

    shared actual Ptr<I64Type> transformThenOperation(ThenOperation that) {
        value cond = that.leftOperand.transform(this);

        scope.body.mark(that, llvmNull);

        value [trueBlock, falseBlock] = scope.body.branch(checkTrue(cond));

        scope.body.block = trueBlock;
        scope.body.mark(that, that.rightOperand.transform(this));
        scope.body.jump(falseBlock);

        scope.body.block = falseBlock;

        assert(exists ret = scope.body.getMarked(ptr(i64), that));
        return ret;
    }

    shared actual Ptr<I64Type> transformWithinOperation(WithinOperation that) {
        value center = that.operand.transform(this);
        value left = that.lowerBound.endpoint.transform(this);
        value largerComparison = getLanguageValue("larger");
        value smallerComparison = getLanguageValue("smaller");
        value trueValue = getLanguageValue("true");
        value falseValue = getLanguageValue("false");

        I1 doCompare(Ptr<I64Type> a, Ptr<I64Type> b, Bound bound, Boolean first) {
            value term = if (first) then bound.endpoint else that.operand;
            value got = scope.callI64(termGetMemberName(term, "compare"), a, b);

            if (bound is OpenBound) {
                return scope.body.compareEq(got, smallerComparison);
            } else {
                return scope.body.compareNE(got, largerComparison);
            }
        }

        value comp_a = doCompare(left, center, that.lowerBound, true);
        scope.body.mark(that, falseValue);
        value [pass, fail] = scope.body.branch(comp_a);

        scope.body.block = pass;

        value right = that.upperBound.endpoint.transform(this);
        value comp_b = doCompare(center, right, that.upperBound, false);
        value result = scope.body.select(comp_b, ptr(i64), trueValue, falseValue);
        scope.body.mark(that, result);
        scope.body.jump(fail);
        scope.body.block = fail;

        assert(exists ret = scope.body.getMarked(ptr(i64), that));
        return ret;
    }

    shared actual Ptr<I64Type> transformElseOperation(ElseOperation that) {
        value val = that.leftOperand.transform(this);

        scope.body.mark(that, val);

        value comparison = scope.body.compareEq(val, llvmNull);

        value [trueBlock, falseBlock] = scope.body.branch(comparison);

        scope.body.block = trueBlock;
        scope.body.mark(that, that.rightOperand.transform(this));
        scope.body.jump(falseBlock);

        scope.body.block = falseBlock;

        assert(exists ret = scope.body.getMarked(ptr(i64), that));
        return ret;
    }

    shared actual Ptr<I64Type> transformNegationOperation(NegationOperation that)
        => scope.callI64(termGetGetterName(that.operand, "negated"),
                that.operand.transform(this));

    shared actual Ptr<I64Type> transformComparisonOperation(
            ComparisonOperation that) {
        value left = that.leftOperand.transform(this);
        value right = that.rightOperand.transform(this);
        value largerComparison = getLanguageValue("larger");
        value smallerComparison = getLanguageValue("smaller");
        value trueValue = getLanguageValue("true");
        value falseValue = getLanguageValue("false");
        value compared = scope.callI64(termGetMemberName(that.leftOperand, "compare"),
                left, right);

        value bool = switch(that)
            case(is LargerOperation)
                scope.body.compareEq(largerComparison, compared)
            case(is SmallerOperation)
                scope.body.compareEq(smallerComparison, compared)
            case(is LargeAsOperation)
                scope.body.compareNE(smallerComparison, compared)
            case(is SmallAsOperation)
                scope.body.compareNE(largerComparison, compared);

        return scope.body.select(bool, ptr(i64), trueValue, falseValue);
    }

    shared actual Ptr<I64Type> transformLogicalOperation(
            LogicalOperation that) {
        value trueValue = getLanguageValue("true");
        value falseValue = getLanguageValue("false");

        if (is AndOperation that) {
            scope.body.mark(that, falseValue);
        } else {
            scope.body.mark(that, trueValue);
        }

        value first = that.leftOperand.transform(this);
        value firstSuccess = scope.body.compareEq(first, trueValue);
        value [trueBlock, falseBlock] = scope.body.branch(firstSuccess);

        value returnLabel = if (is AndOperation that)
            then falseBlock
            else trueBlock;

        scope.body.block = if (is AndOperation that)
            then trueBlock
            else falseBlock;

        scope.body.mark(that, that.rightOperand.transform(this));
        scope.body.jump(returnLabel);
        scope.body.block = returnLabel;

        assert(exists ret = scope.body.getMarked(ptr(i64), that));
        return ret;
    }

    shared actual Ptr<I64Type> transformPostfixIncrementOperation(
            PostfixIncrementOperation that) {
        value ret = that.operand.transform(this);
        value tmp = scope.callI64(termGetGetterName(that.operand, "successor"),
                ret);
        assignTerm(that.operand, tmp);
        return ret;
    }

    shared actual Ptr<I64Type> transformPostfixDecrementOperation(
            PostfixDecrementOperation that) {
        value ret = that.operand.transform(this);
        value tmp = scope.callI64(termGetGetterName(that.operand, "predecessor"),
                ret);
        assignTerm(that.operand, tmp);
        return ret;
    }

    shared actual Ptr<I64Type> transformPrefixIncrementOperation(
            PrefixIncrementOperation that) {
        value start = that.operand.transform(this);
        value ret = scope.callI64(termGetGetterName(that.operand, "successor"), start);
        assignTerm(that.operand, ret);
        return ret;
    }

    shared actual Ptr<I64Type> transformPrefixDecrementOperation(
            PrefixDecrementOperation that) {
        value start = that.operand.transform(this);
        value ret = scope.callI64(termGetGetterName(that.operand, "predecessor"), start);
        assignTerm(that.operand, ret);
        return ret;
    }

    Ptr<I64Type> makeTuple([Ptr<I64Type>*] values,
            variable Ptr<I64Type> end) {
        value tupleClass = getLanguageDeclaration("Tuple");

        for (item in values.reversed) {
            end = scope.callI64(declarationName(tupleClass), item, end);
        }

        return end;
    }

    value emptyType {
        assert(is ValueModel v = getLanguageDeclaration("empty"));
        return v.type;
    }

    /* TODO: support comprehension arguments in tuples */
    [Ptr<I64Type>,TypeModel] getSpreadArg(ArgumentList that)
        => switch (s = that.sequenceArgument)
            case (is SpreadArgument)
                [scope.callI64(termGetMemberName(s.argument, "sequence"),
                        s.argument.transform(this)), termGetType(s.argument)]
            else [getLanguageValue("empty"), emptyType];

    shared actual Ptr<I64Type> transformTuple(Tuple that)
        => that.argumentList.transform(this);

    shared actual Ptr<I64Type> transformPositionalArguments(
            PositionalArguments that)
        => that.argumentList.transform(this);

    shared actual Ptr<I64Type> transformArgumentList(ArgumentList that)
        => makeTuple(that.listedArguments.collect((x) => x.transform(this)),
                getSpreadArg(that)[0]);

    /* TODO: Character literals */
    shared actual Ptr<I64Type> transformCharacterLiteral(CharacterLiteral that)
        => llvmNull;

    shared actual Ptr<I64Type> transformElementOrSubrangeExpression(
            ElementOrSubrangeExpression that) {
        value primary = that.primary.transform(this);

        value name = switch(s = that.subscript)
            case(is KeySubscript) "get"
            case(is SpanSubscript) "span"
            case(is MeasureSubscript) "measure"
            case(is SpanFromSubscript) "spanFrom"
            case(is SpanToSubscript) "spanTo";

        return scope.callI64(termGetMemberName(that.primary, name), primary,
                *that.subscript.children.collect((x) => x.transform(this)));
    }

    shared actual Ptr<I64Type> transformStringTemplate(
            StringTemplate that) {
        value literals = that.literals*.transform(this);
        value expressions = that.expressions.map((x)
            => scope.callI64(termGetGetterName(x, "string"),
                x.transform(this)));
        value stringCat = getLanguageDeclaration("String")
            .getMember("plus", null, false);
        value stringCatName = declarationName(stringCat);

        value flat = foldPairs({}, ({Ptr<I64Type>*} x, Ptr<I64Type> y, Ptr<I64Type> z)
                => x.chain{y,z}, literals, expressions);
        value complete = if (literals.size > expressions.size)
            then flat.chain{literals.last}
            else flat;

        assert(exists ret = complete.reduce((Ptr<I64Type> x, Ptr<I64Type> y)
                => scope.callI64(stringCatName, x, y)));
        return ret;
    }

    shared actual Ptr<I64Type> transformExistsOperation(ExistsOperation that) {
        value trueValue = getLanguageValue("true");
        value falseValue = getLanguageValue("false");
        value testValue = that.operand.transform(this);

        return scope.body.select(scope.body.compareEq(testValue, llvmNull),
                ptr(i64), trueValue, falseValue);
    }

    shared actual Ptr<I64Type> transformObjectExpression(ObjectExpression d) {
        assert(is Tree.ObjectExpression tc = d.get(keys.tcNode));

        try(builder.constructorScope(tc.anonymousClass)) {
            d.extendedType?.visit(builder);
            d.body.visit(builder);
        }

        value context = scope.getContextFor(tc.anonymousClass);

        return scope.callI64(declarationName(tc.anonymousClass),
                *{context}.coalesced);
    }

    shared actual Ptr<I64Type> transformSwitchClause(SwitchClause that) {
        value switched = that.switched;

        value expr = if (is Expression switched)
            then switched.transform(this)
            else
                switched.specifier.expression.transform(this);

        if (is SpecifiedVariable switched) {
            assert(is Tree.Variable s = switched.get(keys.tcNode));
            scope.store(s.declarationModel, expr);
        }

        return expr;
    }

    shared actual Ptr<I64Type> transformSwitchCaseElseExpression(
            SwitchCaseElseExpression that) {
        processSwitch(that, builder);
        assert(exists ret = scope.body.getMarked(ptr(i64), that));
        return ret;
    }

    shared actual Ptr<I64Type> transformOfOperation(OfOperation that)
        => that.operand.transform(this);

    /* TODO: Implement iterable literals. */
    shared actual Ptr<I64Type> transformIterable(Iterable that)
        => llvmNull;

    shared actual Ptr<I64Type> transformLetExpression(LetExpression that) {
        that.patterns.visit(builder);

        return that.expression.transform(this);
    }

    /* TODO: Fill this in once we have type meta stuff */
    shared actual Ptr<I64Type> transformIsOperation(IsOperation that)
        => llvmNull;

    /* TODO: Implement the metamodel */
    shared actual Ptr<I64Type> transformTypeMeta(TypeMeta that)
        => llvmNull;

    /* TODO: Implement float literals */
    shared actual Ptr<I64Type> transformFloatLiteral(FloatLiteral that)
        => llvmNull;
}
