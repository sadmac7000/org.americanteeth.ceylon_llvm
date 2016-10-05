import ceylon.ast.core {
    Condition,
    BooleanCondition,
    Conditions
}


import com.redhat.ceylon.model.typechecker.model {
    Package
}

I1 transformCondition(Condition c, Scope scope, Package languagePackage,
        ExpressionTransformer expressionTransformer) {
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

void transformConditions(Conditions cs, Scope scope, Package languagePackage,
        ExpressionTransformer expressionTransformer, Label trueBlock,
        Label falseBlock) {
    value lastCondition = cs.conditions.last;

    for (condition in cs.conditions) {
        value conditionValue = transformCondition(condition, scope,
                languagePackage, expressionTransformer);

        Label? next = if (lastCondition == condition)
            then trueBlock else null;

        value [nextBlock, _] = scope.body.branch(conditionValue, next,
                falseBlock);
        scope.body.block = nextBlock;
    }
}
