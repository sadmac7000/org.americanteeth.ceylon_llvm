import ceylon.ast.core { ... }
import ceylon.language.meta { type }
import ceylon.collection { HashMap, ArrayList }
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

    "Type info blocks"
    value typeInfos = ArrayList<String>();

    "Entry point (the run function)"
    variable String? entry = null;

    "Symbol prefix for module isolation"
    variable String symPrefix = "";

    "Whether we're in the root package of this module"
    variable Boolean inRoot = false;

    shared actual void visitModuleCompilationUnit(ModuleCompilationUnit m) {}
    shared actual void visitPackageCompilationUnit(PackageCompilationUnit m) {}

    shared actual void visitCompilationUnit(CompilationUnit c) {
        assert(is Tree.CompilationUnit tc = c.get(keys.tcNode));

        assert(is Package pkgNode = tc.unit.\ipackage);
        symPrefix = namePrefix(pkgNode);

        inRoot = pkgNode.\imodule.rootPackage == pkgNode;

        c.visitChildren(this);
        variable String result = "declare i64* @print(i64*)
                                  define private i64* @cMS4xLjE.ceylon.language.print\
                                  (i64* %val) {
                                      %r = call i64* @print(i64* %val)
                                      ret i64* %r
                                  }\n\n";

        for (t in typeInfos) {
            result += "``t``\n";
        }

        if (! typeInfos.empty) { result += "\n"; }

        for (strIn->id in strings) {
            value [str, sz] = processEscapes(strIn);
            result += "@.str``id``.data = private unnamed_addr constant \
                       [``sz`` x i8] c\"``str``\"
                       @.str``id``.object = private unnamed_addr constant \
                       [3 x i64] [i64 0, i64 ``sz``, \
                       i64 ptrtoint([``sz`` x i8]* @.str``id``.data to i64)]
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
                result += "``data``\n\n";
            }
        }

        c.put(keys.llvmData, result);
    }

    shared actual void visitValueDefinition(ValueDefinition v) {
        assert(is Tree.AttributeDeclaration tv = v.get(keys.tcNode));
        value pkg = tv.declarationModel.container;

        value name = "``namePrefix(pkg)``.``tv.identifier.text``";

        assert(is Specifier s = v.definition);
        s.expression.visit(this);
        assert(exists assignment = s.expression.get(keys.llvmData));
        v.put(keys.llvmData, "@``name`` = global i64* ``assignment``
                              define i64* @``name``$get() {
                                  %_ = load i64** @``name``
                                  ret i64* %_
                              }\n");
    }

    shared actual void visitBaseExpression(BaseExpression b) {
        assert(is Tree.BaseMemberExpression tb = b.get(keys.tcNode));
        value pkg = tb.declaration.container;

        b.put(keys.llvmData,
                LLVMExpression(["call i64* @``namePrefix(pkg)``.``tb.identifier.text``$get()"]));
    }

    shared actual void visitClassDefinition(ClassDefinition c) {
        assert(is Tree.ClassDefinition tc = c.get(keys.tcNode));
        value name = namePrefix(tc.declarationModel);

        value typeInfo = "@``name``$typeInfo = global i64 0";
        typeInfos.add(typeInfo);

        c.body.visitChildren(this);

        variable String result = "";

        for (i in c.body.children) {
            if (exists r = i.get(keys.llvmData)) {
                result += "``r``\n";
            }
        }

        c.put(keys.llvmData, result);
    }

    shared actual void visitFunctionDefinition(FunctionDefinition f) {
        f.definition.visit(this);
        value name = "``symPrefix``.``f.name.name``";

        if (f.name.name == "run", inRoot) {
            entry = name;
        }

        assert(exists body = f.definition.get(keys.llvmData));
        f.put(keys.llvmData, "define i64* @``name``() {
                              ``body``
                                  ret i64* null\n}");
    }

    shared actual void visitBlock(Block b) {
        b.visitChildren(this);
        variable String result = "    ";

        for (child in b.children) {
            if (exists data = child.get(keys.llvmData)) {
                result += "``data``\n";
            }
        }

        result = result.replace("\n", "\n    ").replace("    \n", "\n");
        result = result[...result.size - 5];

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

        i.arguments.visit(this);
        assert(is [Anything*] args = i.arguments.get(keys.llvmData));

        value name = m.name.name;

        value spreadable =
            args.narrow<LLVMExpression|String>().map((x) => ["i64* ", x])
                .fold<[LLVMExpression|String *]>([])((x,y) => x.append(y))
                .withTrailing(")")
                .withLeading("call i64* @``prefix``.``name``(");

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
