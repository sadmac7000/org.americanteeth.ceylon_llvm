import ceylon.collection {
    HashMap
}

import ceylon.ast.core {
    Visitor,
    BaseExpression,
    Node,
    Declaration,
    QualifiedExpression,
    ObjectExpression,
    VariablePattern,
    VariadicVariable
}

import org.eclipse.ceylon.compiler.typechecker.tree {
    Tree
}

import org.eclipse.ceylon.model.typechecker.model {
    ScopeModel=Scope,
    FunctionOrValueModel=FunctionOrValue,
    DeclarationModel=Declaration,
    ClassModel=Class,
    ClassOrInterfaceModel=ClassOrInterface,
    ModuleModel=Module,
    TypeModel=Type
}

import ceylon.interop.java {
    CeylonList
}

"An ordering for declarations that says when we should initialize their
 vtables"
HashMap<DeclarationModel,Integer> declarationOrder =
    HashMap<DeclarationModel,Integer>();

"Counters for local variable qualifiers."
HashMap<[DeclarationModel,String],Integer> nextQualifier =
    HashMap<[DeclarationModel,String],Integer>();

"Preprocess the AST. Responsibilities include marking captured variables and
 setting table initialization order."
object preprocessVisitor satisfies Visitor {
    "Backing store for the current scope"
    variable ScopeModel? current_ = null;

    "The current scope. Asserts that we are currently within a scope"
    ScopeModel current {
        "Current scope should be set"
        assert (exists c = current_);
        return c;
    }

    shared actual void visitNode(Node that)
        => that.visitChildren(this);

    "Mark a declaration with a number that gives an inheritance ordering of all
     declarations."
    void markDeclarationOrder(ClassOrInterfaceModel d) {
        variable ModuleModel mod = d.unit.\ipackage.\imodule;

        Integer? doMark(ClassOrInterfaceModel cur) {
            if (cur.unit.\ipackage.\imodule != mod) {
                return null;
            }

            if (declarationOrder.defines(cur)) {
                return declarationOrder[cur];
            }

            Integer? doMarkForType(TypeModel t) {
                assert (is ClassOrInterfaceModel m = t.declaration);
                return doMark(m);
            }

            Integer satisfiedMax =
                max(CeylonList(cur.satisfiedTypes).map(doMarkForType)
                        .narrow<Integer>()) else -1;

            if (is ClassModel cur,
                exists t = cur.extendedType,
                exists j = doMarkForType(t),
                j > satisfiedMax) {
                declarationOrder.put(cur, j + 1);
                return j + 1;
            } else {
                declarationOrder.put(cur, satisfiedMax + 1);
                return satisfiedMax + 1;
            }
        }

        doMark(d);
    }

    void setQualifier(DeclarationModel scope) {
        if (scope.qualifier exists) {
            return;
        }

        if (scope.toplevel) {
            return;
        }

        assert(is DeclarationModel container =
                nearestAllocatingScope(scope.container));

        if (scope.\ishared) {
            return;
        }

        value qualifier = nextQualifier[[container,scope.name]] else 1;
        nextQualifier[[container,scope.name]] = qualifier + 1;
        scope.qualifier = qualifier.string;
    }

    shared actual void visitDeclaration(Declaration that) {
        assert (is Tree.Declaration tc = that.get(keys.tcNode));

        value scope = if (is Tree.ObjectDefinition tc)
                      then tc.anonymousClass
                      else tc.declarationModel;

        if (! baremetalSupports(scope)) {
            return;
        }

        setQualifier(scope);

        if (is ClassOrInterfaceModel scope) {
            markDeclarationOrder(scope);
        }

        if (!is ScopeModel scope) {
            return;
        }

        value old = current_;
        current_ = scope;
        that.visitChildren(this);
        current_ = old;
    }

    "Set the captured property on a used symbol if it needs it."
    void setCapturedIfNeeded(DeclarationModel declaration) {
        if (!is FunctionOrValueModel declaration) {
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

        if (exists s = declaration.scope) {
            declaration.captured = s != current;
        } else {
            declaration.captured = false;
        }
    }

    shared actual void visitBaseExpression(BaseExpression that)
            => setCapturedIfNeeded(termGetDeclaration(that));

    shared actual void visitQualifiedExpression(QualifiedExpression that)
            => setCapturedIfNeeded(termGetDeclaration(that));

    shared actual void visitObjectExpression(ObjectExpression that) {
        assert(is Tree.ObjectExpression tc = that.get(keys.tcNode));
        markDeclarationOrder(tc.anonymousClass);
        that.visitChildren(this);
    }

    shared actual void visitVariablePattern(VariablePattern that) {
        value declaration = termGetDeclaration(that.\ivariable);
        setCapturedIfNeeded(declaration);
        setQualifier(declaration);
    }

    shared actual void visitVariadicVariable(VariadicVariable that) {
        value declaration = termGetDeclaration(that);
        setCapturedIfNeeded(declaration);
        setQualifier(declaration);
    }
}
