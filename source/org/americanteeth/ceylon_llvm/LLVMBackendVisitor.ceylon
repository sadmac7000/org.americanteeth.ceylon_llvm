import ceylon.ast.core { ... }

class UnsupportedNode() extends Exception() {}

Key<Object> llvmData = ScopedKey<Object>(`module`, "llvmData");

class LLVMBackendVisitor() satisfies Visitor {
    shared actual void visitCompilationUnit(CompilationUnit c) {
        c.visitChildren(this);
        variable String result = "declare void @probeFunc()\n";

        for (child in c.children) {
            if (exists data = child.get(llvmData)) {
                result += "``data``\n";
            }
        }

        c.put(llvmData, result);
    }

    shared actual void visitFunctionDefinition(FunctionDefinition f) {
        if (f.name.name == "probeFunc") { return; }

        f.definition.visit(this);
        assert(exists body = f.definition.get(llvmData));
        f.put(llvmData, "define void @``f.name.name``() {\n``body``\nret void\n}");
    }

    shared actual void visitBlock(Block b) {
        b.visitChildren(this);
        variable String result = "";

        for (child in b.children) {
            if (exists data = child.get(llvmData)) {
                result += "``data``\n";
            }
        }

        b.put(llvmData, result);
    }

    shared actual void visitInvocationStatement(InvocationStatement i) {
        i.expression.visit(this);
        assert(exists d = i.expression.get(llvmData));
        i.put(llvmData, d);
    }

    shared actual void visitInvocation(Invocation i) {
        assert(is BaseExpression b = i.invoked);
        assert(is MemberNameWithTypeArguments m = b.nameAndArgs);

        String name = m.name.name;
        i.put(llvmData, "call void @``name``()");
    }

    shared actual void visitNode(Node that) {
        throw UnsupportedNode();
    }
}
