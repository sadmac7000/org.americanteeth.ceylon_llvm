import ceylon.ast.core { ... }

class UnsupportedNode() extends Exception() {}

class LLVMBackendVisitor() satisfies Visitor {
    shared actual void visitCompilationUnit(CompilationUnit c) {
        c.visitChildren(this);
    }

    shared actual void visitFunctionDefinition(FunctionDefinition f) {
        print("define void @``f.name.name``() { ret void }");
    }

    shared actual void visitNode(Node that) {
        throw UnsupportedNode();
    }
}
