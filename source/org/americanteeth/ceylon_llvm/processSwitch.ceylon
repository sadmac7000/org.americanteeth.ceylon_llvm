import ceylon.ast.core {
    Expression,
    SwitchCaseElse,
    SwitchCaseElseExpression,
    CaseItem,
    CaseClause,
    IsCase
}

import ceylon.collection {
    ArrayList
}

void processSwitch(SwitchCaseElse|SwitchCaseElseExpression sw,
        LLVMBuilder builder) {
    value clause = if (is SwitchCaseElse sw) then sw.clause else sw.clause;
    value cases = if (is SwitchCaseElse sw) then sw.cases.caseClauses else sw.caseExpressions;
    value elseItem = if (is SwitchCaseElse sw)
        then sw.cases.elseClause?.child
        else sw.elseExpression;
    value scope => builder.scope;
    value expressionTransformer => builder.expressionTransformer;

    value expr = clause.transform(expressionTransformer);

    Label[2] processCaseItem(CaseItem item) {
        if (is IsCase item) {
            /* TODO: Handle this correctly when we have metamodel types */
            return scope.body.branch(I1Lit(0));
        }

        value branch = item.expressions.map((x) =>
                scope.body.compareEq(x.transform(expressionTransformer), expr))
            .reduce<I1>((x, y) => scope.body.or(i1, x, y));

        return scope.body.branch(branch);
    }

    value blocks = ArrayList<Label>();

    for (item in cases) {
        value caseItem = if (is CaseClause item)
            then item.caseItem
            else item.caseItem;
        let ([trueBlock, falseBlock] = processCaseItem(caseItem));
        scope.body.block = trueBlock;
        if (is CaseClause item) {
            item.block.visit(builder);
        } else {
            value got = item.expression.transform(expressionTransformer);
            scope.body.mark(sw, got);
        }
        blocks.add(scope.body.block);
        scope.body.block = falseBlock;
    }

    if (exists elseItem) {
        if (is Expression elseItem) {
            scope.body.mark(sw, elseItem.transform(expressionTransformer));
        } else {
            elseItem.visit(builder);
        }
        scope.body.splitBlock();
    } else if (is SwitchCaseElseExpression sw) {
        scope.body.unreachable();
        scope.body.splitBlock();
    }

    value endPoint = scope.body.block;

    for (block in blocks) {
        scope.body.block = block;
        if (! scope.body.blockTerminated()) {
            scope.body.jump(endPoint);
        }
    }

    scope.body.block = endPoint;
}
