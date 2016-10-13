import ceylon.ast.core {
    Node
}

import com.redhat.ceylon.compiler.typechecker.tree {
    Tree
}

import com.redhat.ceylon.model.typechecker.model {
    DeclarationModel=Declaration,
    TypeModel=Type
}

import ceylon.interop.java {
    CeylonMap
}

"Get a declaration for a member of the type of a given term node."
DeclarationModel termGetMember(Node that, String member)
    => termGetType(that).declaration.getMember(member, null, false);

"Get the fully-qualified name of a member of the type of a given term node."
String termGetMemberName(Node that, String member)
    => declarationName(termGetMember(that, member));

String termGetGetterName(Node that, String member)
    => getterName(termGetMember(that, member));

"Get a declaration for the value in a given term node."
DeclarationModel termGetDeclaration(Node that) {
    value tc = that.get(keys.tcNode);
    if (is Tree.MemberOrTypeExpression tc) {
        return tc.declaration;
    } else if (is Tree.Variable tc) {
        return tc.declarationModel;
    } else {
        assert(false);
    }
}

"Get a type model for the value in a given term node."
TypeModel termGetType(Node that) {
    assert(is Tree.Term tc = that.get(keys.tcNode));
    return tc.typeModel;
}

"Get type argument by name from a term's type."
TypeModel termGetTypeArgument(Node that, String argument) {
    value parentType = termGetType(that);

    for (declaration->type in CeylonMap(parentType.typeArguments)) {
        if (declaration.name == argument) {
            return type;
        }
    }

    "We should always find the requested argument"
    assert(false);
}
