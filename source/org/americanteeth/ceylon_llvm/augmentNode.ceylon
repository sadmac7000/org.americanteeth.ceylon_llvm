import ceylon.ast.core {
    Node
}
import ceylon.interop.java {
    CeylonList
}

import com.redhat.ceylon.compiler.typechecker.tree {
    TcNode=Node,
    Tree
}

void augmentNode(TcNode tcNode, Node node) {
    node.put(keys.location, tcNode.location);
    node.put(keys.tcNode, tcNode);
}
