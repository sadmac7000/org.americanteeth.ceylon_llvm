import ceylon.ast.core {
    ...
}

import ceylon.collection {
    ArrayList,
    HashMap
}

import com.redhat.ceylon.compiler.typechecker.tree {
    Tree
}

import com.redhat.ceylon.model.typechecker.model {
    PackageModel=Package,
    FunctionOrValueModel=FunctionOrValue
}

class ExpressionTransformer(Scope() scopeGetter, PackageModel languagePackage)
        satisfies WideningTransformer<Ptr<I64Type>> {

    "The next string literal ID available"
    variable value nextStringLiteral = 0;

    "A table of all string literals"
    value stringLiterals = HashMap<Integer,String>();

    value scope => scopeGetter();

    "Get a value from the root of the language module."
    Ptr<I64Type> getLanguageValue(String name) {
        value declaration = languagePackage.getDirectMember(name, null, false);
        return scope.callI64(getterName(declaration));
    }

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

    shared actual Nothing transformNode(Node that) {
        throw UnsupportedNode(that);
    }

    shared actual Ptr<I64Type> transformStringLiteral(StringLiteral that) {
        value idNumber = nextStringLiteral++;
        stringLiterals.put(idNumber, that.text);
        return scope.body.global(i64, ".str``idNumber``");
    }

    shared actual Ptr<I64Type> transformInvocation(Invocation that) {
        "We don't support expression callables yet"
        assert (is BaseExpression|QualifiedExpression b = that.invoked);

        value declaration = termGetDeclaration(that.invoked);
        value arguments = ArrayList<Ptr<I64Type>>();

        /* TODO */
        "We don't support named arguments yet"
        assert (is PositionalArguments pa = that.arguments);

        /* TODO: Sequence arguments */

        value sup = if (is QualifiedExpression b, b.receiverExpression is Super)
            then true else false;

        if (is QualifiedExpression b,
            ! b.receiverExpression is Super|Package|This) {
            arguments.add(b.receiverExpression.transform(this));
        } else if (exists f = scope.getContextFor(declaration, sup)) {
            arguments.add(f);
        }

        String functionName;

        if (is QualifiedExpression b, b.receiverExpression is Super) {
            functionName = dispatchName(declaration);
        } else {
            functionName = declarationName(declaration);
        }

        for (arg in pa.argumentList.listedArguments) {
            arguments.add(arg.transform(this));
        }

        return scope.callI64(functionName, *arguments);
    }

    shared actual Ptr<I64Type> transformBaseExpression(BaseExpression that)
        => scope.load(termGetDeclaration(that));

    shared actual Ptr<I64Type> transformQualifiedExpression(QualifiedExpression that) {
        "TODO: Support fancy member operators"
        assert (that.memberOperator is MemberOperator);

        return scope.callI64(getterName(termGetDeclaration(that)),
                that.receiverExpression.transform(this));
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

        "TODO: make element assignment work"
        assert(is BaseExpression|QualifiedExpression term);

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
        package.transformConditions(that.conditions, scope, languagePackage, this,
                trueBlock, falseBlock);

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
            => scope.callI64(termGetMemberName(that.leftOperand, name), left, right);

        Ptr<I64Type> opR(String name)
            => scope.callI64(termGetMemberName(that.rightOperand, name), right, left);

        Ptr<I64Type> opS(String name) {
            value target = languagePackage.getDirectMember(name, null, false);
            return scope.callI64(declarationName(target), left, right);
        }


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

    shared actual Ptr<I64Type> transformTuple(Tuple that) {
        value tupleClass = languagePackage.getDirectMember("Tuple", null, false);
        value emptyObject = getLanguageValue("empty");

        /* TODO: support spread and comprehension arguments in tuples */
        variable Ptr<I64Type> end = emptyObject;

        for (item in that.argumentList.listedArguments.reversed) {
            end = scope.callI64(declarationName(tupleClass), item.transform(this), end);
        }

        return end;
    }

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
        value stringCat = languagePackage.getDirectMember("String", null,
                false).getMember("plus", null, false);
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
}
