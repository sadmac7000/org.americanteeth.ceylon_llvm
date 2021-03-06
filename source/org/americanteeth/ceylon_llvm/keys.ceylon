import ceylon.ast.core {
    Key,
    ScopedKey
}

import org.eclipse.ceylon.compiler.typechecker.tree {
    TcNode=Node
}

object keys {
    shared Key<TcNode> tcNode = ScopedKey<TcNode>(`value keys`, "tcNode");
    shared Key<String> location = ScopedKey<String>(`value keys`, "location");
}
