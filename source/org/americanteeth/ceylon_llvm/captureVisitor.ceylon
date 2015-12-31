import ceylon.ast.core {
    Visitor,
    BaseExpression,
    Node,
    Declaration,
    QualifiedExpression,
    This
}

import com.redhat.ceylon.compiler.typechecker.tree {
    Tree
}

import com.redhat.ceylon.model.typechecker.model {
    ScopeModel = Scope,
    FunctionOrValueModel = FunctionOrValue
}

object captureVisitor satisfies Visitor {
    "Backing store for the current scope"
    variable ScopeModel? current_ = null;

    "The current scope. Asserts that we are currently within a scope"
    ScopeModel current {
        "Current scope should be set"
        assert(exists c = current_);
        return c;
    }

    shared actual void visitNode(Node that)
        => that.visitChildren(this);

    shared actual void visitDeclaration(Declaration that) {
        assert(is Tree.Declaration tc = that.get(keys.tcNode));

        value scope = tc.declarationModel;

        if (! is ScopeModel scope) {
            return;
        }

        value old = current_;
        current_ = scope;
        that.visitChildren(this);
        current_ = old;
    }

    shared actual void visitBaseExpression(BaseExpression that) {
        assert(is Tree.BaseMemberOrTypeExpression tb = that.get(keys.tcNode));
        value declaration = tb.declaration;

        if (! is FunctionOrValueModel declaration) {
            return;
        }

        if (declaration.captured) {
            return;
        }

        if (declaration.toplevel) {
            return;
        }

        if (declaration.\ishared) {
            return;
        }

        declaration.captured = declaration.scope != current;
    }

    shared actual void visitQualifiedExpression(QualifiedExpression that) {
        if (! that.receiverExpression is This) {
            return;
        }

        "TODO: Implement capture for this.*"
        assert(false);
    }
}
