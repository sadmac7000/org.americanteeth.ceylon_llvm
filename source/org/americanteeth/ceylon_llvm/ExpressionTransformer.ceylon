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

        "We don't support named arguments yet"
        assert (is PositionalArguments pa = that.arguments);

        "We don't support sequence arguments yet"
        assert (!pa.argumentList.sequenceArgument exists);

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

        return scope.body.call(ptr(i64), functionName, *arguments);
    }

    shared actual Ptr<I64Type> transformBaseExpression(BaseExpression that) {
        assert (is FunctionOrValueModel declaration = termGetDeclaration(that));
        return scope.access(declaration);
    }

    shared actual Ptr<I64Type> transformQualifiedExpression(QualifiedExpression that) {
        "TODO: Support fancy member operators"
        assert (that.memberOperator is MemberOperator);

        return scope.body.call(ptr(i64), getterName(termGetDeclaration(that)),
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
        value trueIdentifier = languagePackage.getDirectMember("true", null,
                false);
        value falseIdentifier = languagePackage.getDirectMember("false", null,
                false);
        value trueObject = scope.body.call(ptr(i64),
                getterName(trueIdentifier));
        value falseObject = scope.body.call(ptr(i64),
                getterName(falseIdentifier));
        value expression = that.operand.transform(this);
        value test = scope.body.compareEq(expression, trueObject);

        return scope.body.select(test, ptr(i64), falseObject, trueObject);
    }

    shared actual Ptr<I64Type> transformInOperation(InOperation that) {
        value elementValue = that.element.transform(this);
        value categoryValue = that.category.transform(this);
        value containsDeclaration = termGetMember(that.category, "contains");
        return scope.body.call(ptr(i64), declarationName(containsDeclaration),
                categoryValue, elementValue);
    }

    /* TODO: Implement this once we have callable support */
    shared actual Ptr<I64Type> transformFunctionExpression(
            FunctionExpression that) => llvmNull;

    /* TODO: Design and implement integer literals */
    shared actual Ptr<I64Type> transformIntegerLiteral(
            IntegerLiteral that) => llvmNull;

    shared actual Ptr<I64Type> transformEqualOperation(EqualOperation that) {
        value leftOperand = that.leftOperand.transform(this);
        value rightOperand = that.leftOperand.transform(this);
        value equalsFunction = termGetMember(that.leftOperand, "equals");
        return scope.body.call(ptr(i64), declarationName(equalsFunction),
                leftOperand, rightOperand);
    }

    shared actual Ptr<I64Type> transformAssignmentOperation(AssignmentOperation that) {
        value transformedRight = that.rightOperand.transform(this);
        value toAssign = switch(that)
            case (is AssignOperation) transformedRight
            else null;

        "TODO: Support fancy assignment"
        assert(exists toAssign);

        "We can only assign to base expressions, qualified expressions, or
         Element/Subrange expressions"
        assert(
            is BaseExpression|QualifiedExpression|ElementOrSubrangeExpression
                leftOperand = that.leftOperand);

        "TODO: make element assignment work"
        assert(is BaseExpression|QualifiedExpression leftOperand);

        assert(is FunctionOrValueModel declaration =
                termGetDeclaration(that.leftOperand));

        if (is BaseExpression leftOperand) {
            scope.store(declaration, toAssign);
        } else {
            scope.body.call(ptr(i64), setterName(declaration),
                    leftOperand.receiverExpression.transform(this),
                    toAssign);
        }

        return toAssign;
    }
}

