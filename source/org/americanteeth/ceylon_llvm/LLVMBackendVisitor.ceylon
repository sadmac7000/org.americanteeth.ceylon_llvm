import ceylon.ast.core { ... }
import ceylon.language.meta { type }
import ceylon.collection { HashMap }
import ceylon.io.base64 { encodeUrl }
import ceylon.io.charset { utf8 }

import com.redhat.ceylon.compiler.typechecker.tree {
    Tree
}

import ceylon.interop.java {
    CeylonList
}

class UnsupportedNode(String s) extends Exception(s) {}

class LLVMBackendVisitor() satisfies Visitor {
    "The string table"
    value strings = HashMap<String,Integer>();

    "Next available string table ID"
    variable value nextString = 0;

    "Get an ID number for a string in the string table"
    Integer getStringID(String s) {
        value gotten = strings[s];

        if (exists gotten) { return gotten; }

        strings.put(s, nextString);
        return nextString++;
    }

    "Name of the module we're visiting"
    variable String mod = "default";

    "Version of the module we're visiting"
    variable String? version = null;

    "Entry point (the run function)"
    variable String? entry = null;

    "Identifier-safe version"
    String encodedVersion
        => if (exists v=version)
        then utf8.decode(encodeUrl(utf8.encode(v)))
            .replace("_", "__")
            .replace("=", "_e")
            .replace("-", "_h")
        else "";

    "Name of the package we're visiting"
    variable String pkg = "default";

    "Symbol prefix for module isolation"
    String symPrefix => "c``encodedVersion``.``pkg``";

    shared actual void visitModuleCompilationUnit(ModuleCompilationUnit m) {}
    shared actual void visitPackageCompilationUnit(PackageCompilationUnit m) {}

    shared actual void visitCompilationUnit(CompilationUnit c) {
        assert(is Tree.CompilationUnit tc = c.get(keys.tcNode));

        value pkgNode = tc.unit.\ipackage;
        value modNode = pkgNode.\imodule;

        mod = CeylonList(modNode.name).reduce<String>((x, y) => x.string +
                ".``y.string``")?.string
            else "";
        version = modNode.version;
        pkg = CeylonList(pkgNode.name).reduce<String>((x, y) => x.string +
                ".``y.string``")?.string
            else "";

        c.visitChildren(this);
        variable String result = "declare i64* @print(i64*)\n";

        for (strIn->id in strings) {
            value [str, sz] = processEscapes(strIn);
            result += "@.str``id``.data = private unnamed_addr constant \
                       [``sz`` x i8] c\"``str``\"
                       @.str``id``.object = private unnamed_addr constant \
                       [3 x i64] [i64 0, i64 ``sz``, \
                       i64 ptrtoint([``sz`` x i8]* \
                       @.str``id``.data to i64)]
                       @.str``id`` = alias private i64* \
                       bitcast([3 x i64]* @.str``id``.object to i64*)\n";
        }

        if (! strings.empty) {
            result += "\n";
        }

        if (exists e = entry) {
            result += "@ceylon_run = alias i64*()* @``e``\n\n";
        }

        for (child in c.children) {
            if (exists data = child.get(keys.llvmData)) {
                result += "``data``\n";
            }
        }

        c.put(keys.llvmData, result);
    }

    shared actual void visitFunctionDefinition(FunctionDefinition f) {
        f.definition.visit(this);
        value name = "``symPrefix``.``f.name.name``";

        if (f.name.name == "run", pkg == mod) {
            entry = name;
        }

        assert(exists body = f.definition.get(keys.llvmData));
        f.put(keys.llvmData, "define i64* @\"``name``\"() {
                              ``body``
                              ret i64* null\n}");
    }

    shared actual void visitBlock(Block b) {
        b.visitChildren(this);
        variable String result = "";

        for (child in b.children) {
            if (exists data = child.get(keys.llvmData)) {
                result += "``data``\n";
            }
        }

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

        "We don't support expression callables yet"
        assert(is MemberNameWithTypeArguments m = b.nameAndArgs);

        i.arguments.visit(this);
        assert(is [Anything*] args = i.arguments.get(keys.llvmData));

        value name = m.name.name;
        value spreadable =
            args.narrow<LLVMExpression|String>().map((x) => ["i64* ", x])
                .fold<[LLVMExpression|String *]>([])((x,y) => x.append(y))
                .withTrailing(")")
                .withLeading("call i64* @``name``(");

        value expr = LLVMExpression(spreadable);
        i.put(keys.llvmData, expr);
    }

    shared actual void visitPositionalArguments(PositionalArguments p) {
        assert(! p.argumentList.sequenceArgument exists);

        value args = p.argumentList.listedArguments;

        for (arg in args) { arg.visit(this); }
        p.put(keys.llvmData, [ for (arg in args) arg.get(keys.llvmData) ]);
    }

    shared actual void visitStringLiteral(StringLiteral s) {
        s.put(keys.llvmData, "@.str``getStringID(s.text)``");
    }

    shared actual void visitNode(Node that) {
        throw UnsupportedNode(type(that).string);
    }
}
