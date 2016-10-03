import ceylon.ast.core {
    Node
}

import com.redhat.ceylon.compiler.typechecker.tree {
    Tree
}

import com.redhat.ceylon.model.typechecker.model {
    DeclarationModel=Declaration
}

"Get a declaration for a member of the type of a given term node."
DeclarationModel termGetMember(Node that, String member) {
    assert(is Tree.Term tc = that.get(keys.tcNode));
    return tc.typeModel.declaration.getMember(member, null, false);
}