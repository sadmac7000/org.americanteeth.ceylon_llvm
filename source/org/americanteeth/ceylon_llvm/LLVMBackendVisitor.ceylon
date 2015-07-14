import ceylon.ast.core { ... }
import ceylon.language.meta { type }
import ceylon.collection { ArrayList }
import ceylon.io.base64 { encodeUrl }
import ceylon.io.charset { utf8 }

import com.redhat.ceylon.compiler.typechecker.tree {
    Tree
}

import com.redhat.ceylon.model.typechecker.model {
    Scope,
    Package,
    TypeDeclaration
}

import ceylon.interop.java {
    CeylonList
}

"Get the name prefix for items in a given package"
String namePrefix(Scope p) {
    if (is TypeDeclaration p) {
        return namePrefix(p.container) + ".$``p.name``";
    }

    assert(is Package p);

    value v = p.\imodule.version;
    value pkg = CeylonList(p.name)
        .reduce<String>((x, y) => x.string + ".``y.string``")?.string;
    assert(exists pkg);

    return "c" + utf8.decode(encodeUrl(utf8.encode(v)))
            .replace("=", "")
            .replace("-", "$") + ".``pkg``";
}

class UnsupportedNode(String s) extends Exception(s) {}

class LLVMBackendVisitor() satisfies Visitor {
    shared actual void visitModuleCompilationUnit(ModuleCompilationUnit m) {}
    shared actual void visitPackageCompilationUnit(PackageCompilationUnit m) {}

    shared actual void visitCompilationUnit(CompilationUnit c) {
        "Java AST node for compilation unit should be a compilation unit node"
        assert(is Tree.CompilationUnit tc = c.get(keys.tcNode));

        "Container for compilation unit should be a package"
        assert(is Package pkgNode = tc.unit.\ipackage);

        c.visitChildren(this);

        value result = llvmCompilationUnit(namePrefix(pkgNode),
                pkgNode.\imodule.rootPackage == pkgNode,
                [ for (ch in c.children)
                    if (exists d = ch.get(keys.llvmData))
                        d ]
                        );

        c.put(keys.llvmData, result);
    }

    shared actual void visitValueDefinition(ValueDefinition v) {
        assert(is Tree.AttributeDeclaration tv = v.get(keys.tcNode));
        value pkg = tv.declarationModel.container;
        assert(is Specifier s = v.definition);

        s.expression.visit(this);
        assert(is LLVMExpression assignment = s.expression.get(keys.llvmData));

        v.put(keys.llvmData, llvmValueDefinition(tv.identifier.text,
                    assignment));
    }

    shared actual void visitBaseExpression(BaseExpression b) {
        assert(is Tree.BaseMemberExpression tb = b.get(keys.tcNode));
        value pkg = tb.declaration.container;

        b.put(keys.llvmData,
                llvmVariableUsage("``namePrefix(pkg)``.``tb.identifier.text``"));
    }

    shared actual void visitReturn(Return r) {
        r.result?.visit(this);
        value val = r.result?.get(keys.llvmData) else llvmNull;
        assert(is LLVMExpression val);
        r.put(keys.llvmData, llvmReturn(val));
    }

    shared actual void visitClassDefinition(ClassDefinition c) {
        assert(is Tree.ClassDefinition tc = c.get(keys.tcNode));
        value name = tc.declarationModel.name;

        c.body.visitChildren(this);

        value decls = [ for (i in c.body.children)
                            if (exists r = i.get(keys.llvmData))
                                r
                      ];

        c.put(keys.llvmData, llvmClass(name, decls));
    }

    shared actual void visitFunctionDefinition(FunctionDefinition f) {
        f.definition.visit(this);

        "Definition visit should create a body"
        assert(exists body = f.definition.get(keys.llvmData));

        f.put(keys.llvmData, llvmMethodDef(f.name.name, [], [body]));
    }

    shared actual void visitBlock(Block b) {
        b.visitChildren(this);

        value result = code([for (child in b.children)
                if (exists d = child.get(keys.llvmData))
                    d]);

        b.put(keys.llvmData, result);
    }

    shared actual void visitInvocationStatement(InvocationStatement i) {
        i.expression.visit(this);
        assert(exists d = i.expression.get(keys.llvmData));
        i.put(keys.llvmData, d);
    }

    shared actual void visitInvocation(Invocation i) {
        "We don't support expression callables yet"
        assert(is BaseExpression b = i.invoked);
        assert(is Tree.BaseMemberExpression bt = b.get(keys.tcNode));
        value callPkg = bt.declaration.container;
        value prefix = namePrefix(callPkg);

        "We don't support expression callables yet"
        assert(is MemberNameWithTypeArguments m = b.nameAndArgs);

        "We don't support named arguments yet"
        assert(is PositionalArguments pa = i.arguments);

        "We don't support sequence arguments yet"
        assert(! pa.argumentList.sequenceArgument exists);

        for (arg in pa.argumentList.listedArguments) {
            arg.visit(this);
        }

        value args = [
            for (arg in pa.argumentList.listedArguments)
                if (is LLVMExpression a = arg.get(keys.llvmData))
                    a
        ];

        i.put(keys.llvmData, llvmInvocation("``prefix``.``m.name.name``", args));
    }

    shared actual void visitStringLiteral(StringLiteral s) {
        s.put(keys.llvmData, llvmStringLiteral(s.text));
    }

    shared actual void visitNode(Node that) {
        throw UnsupportedNode(type(that).string);
    }
}
