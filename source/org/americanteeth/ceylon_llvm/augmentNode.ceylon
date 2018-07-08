import ceylon.ast.core {
    Node
}

import org.eclipse.ceylon.compiler.typechecker.tree {
    TcNode=Node
}

void augmentNode(TcNode tcNode, Node node) {
    node.put(keys.location, tcNode.location);
    node.put(keys.tcNode, tcNode);
}
