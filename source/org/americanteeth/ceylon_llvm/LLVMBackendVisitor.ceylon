import ceylon.ast.core { ... }
import ceylon.language.meta { type }
import ceylon.collection { HashMap }

class UnsupportedNode(String s) extends Exception(s) {}

Key<Object> llvmData = ScopedKey<Object>(`module`, "llvmData");

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

    shared actual void visitCompilationUnit(CompilationUnit c) {
        c.visitChildren(this);
        variable String result = "declare i64* @print(i64*)\n";

        for (str->id in strings) {
            result += "@.str``id``.data = private unnamed_addr constant \
                       [``str.size`` x i8] c\"``str``\"
                       @.str``id``.object = private unnamed_addr constant \
                       [3 x i64] [i64 0, i64 ``str.size``, \
                       i64 ptrtoint([``str.size`` x i8]* \
                       @.str``id``.data to i64)]
                       @.str``id`` = alias i64* \
                       bitcast([3 x i64]* @.str``id``.object to i64*)\n";
        }

        for (child in c.children) {
            if (exists data = child.get(llvmData)) {
                result += "``data``\n";
            }
        }

        c.put(llvmData, result);
    }

    shared actual void visitFunctionDefinition(FunctionDefinition f) {
        f.definition.visit(this);
        assert(exists body = f.definition.get(llvmData));
        f.put(llvmData, "define i64* @``f.name.name``() {\n``body``\n\
                         ret i64* null\n}");
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
        "We don't support expression callables yet"
        assert(is BaseExpression b = i.invoked);

        "We don't support expression callables yet"
        assert(is MemberNameWithTypeArguments m = b.nameAndArgs);

        i.arguments.visit(this);
        assert(is [Anything*] args = i.arguments.get(llvmData));

        value name = m.name.name;
        value spreadable =
            args.narrow<LLVMExpression|String>().map((x) => ["i64* ", x])
                .fold<[LLVMExpression|String *]>([])((x,y) => x.append(y))
                .withTrailing(")")
                .withLeading("call i64* @``name``(");

        value expr = LLVMExpression(spreadable);
        i.put(llvmData, expr);
    }

    shared actual void visitPositionalArguments(PositionalArguments p) {
        assert(! p.argumentList.sequenceArgument exists);

        value args = p.argumentList.listedArguments;

        for (arg in args) { arg.visit(this); }
        p.put(llvmData, [ for (arg in args) arg.get(llvmData) ]);
    }

    shared actual void visitStringLiteral(StringLiteral s) {
        s.put(llvmData, "@.str``getStringID(s.text)``");
    }

    shared actual void visitNode(Node that) {
        throw UnsupportedNode(that.string);
    }
}
