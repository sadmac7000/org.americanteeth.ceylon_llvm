import ceylon.collection { HashMap, ArrayList }

interface Allocation {
    "Get LLVM load instruction"
    shared formal LLVMExpression load;

    "Get LLVM store instruction"
    shared formal String store(Code val);
}

"A chunk of LLVM code"
class Code(shared Code[] children = []) {
    "callback for changes on reparent"
    shared default void onReparent() {
        for (c in children) {
            c.onReparent();
        }
    }

    "Internal variable for parent"
    variable Code? _parent = null;

    "Parent code node"
    shared Code? parent => _parent;

    "Whether this code node is for a declaration inside of a Class or Interface"
    shared default Boolean contained => parent?.contained else false;

    "Name of our package or container"
    shared default String containerName => parent?.containerName else "default";

    "Get a new ID for a temporary variable"
    shared default Integer newTemporaryID() => parent?.newTemporaryID() else 0;

    "Internal variable for runMethod"
    variable LLVMMethodDef? _runMethod = null;

    "Run method exposed by this code"
    shared default LLVMMethodDef? runMethod => _runMethod;

    "String table hashmap, assuming we're root of the string table"
    variable HashMap<String,Integer>? strings = null;

    "Next available string table ID"
    variable value nextString = 0;

    "Get an ID number for a string in the string table"
    shared Integer getStringID(String s) {
        if (exists p = parent) { return p.getStringID(s); }

        if (! strings exists) { strings = HashMap<String,Integer>(); }
        assert(exists table = strings);

        value gotten = table[s];

        if (exists gotten) { return gotten; }

        table.put(s, nextString);
        return nextString++;
    }

    "Get the initial table of string data"
    shared String stringTable {
        variable value result = "";

        if (! strings exists) { return ""; }

        assert(exists table = strings);

        for (strIn->id in table) {
            value [str, sz] = processEscapes(strIn);
            result += "@.str``id``.data = private unnamed_addr constant \
                       [``sz`` x i8] c\"``str``\"
                       @.str``id``.object = private unnamed_addr constant \
                       [3 x i64] [i64 0, i64 ``sz``, \
                       i64 ptrtoint([``sz`` x i8]* @.str``id``.data to i64)]
                       @.str``id`` = alias private i64* \
                       bitcast([3 x i64]* @.str``id``.object to i64*)\n\n";
        }

        return result;
    }

    shared actual default String string
        => "\n".join(children.map((x) => x.string)) + "\n";

    "Change our parent"
    assign parent {
        _parent = parent;
        onReparent();
    }

    "Sometimes I hate this language"
    shared void init() {
        for (c in children) {
            c.parent = this;
            if (exists r = c.runMethod) { _runMethod = r; }
        }
    }

    "A new allocation for variable backing"
    shared default Allocation newAllocation(String shortName, Code? definition)
        => parent?.newAllocation(shortName, definition)
        else object satisfies Allocation {
            shared actual LLVMExpression load {
                object ret extends LLVMExpression() {
                    shared actual String template =>
                        "load i64** @``containerName``.``shortName``";
                }

                ret.init();
                return ret;
            }

            shared actual String store(Code val) => "";
        };
}

Code code(Code[] children = []) {
    value ret = Code(children);
    ret.init();
    return ret;
}

"An expression as LLVM code"
abstract class LLVMExpression(LLVMExpression[] args = [])
        extends Code(args) {
    shared formal String template;

    String apply(String prefix = "") {
        variable value preamble = "";
        variable value instructed = "``prefix````template``";

        for (arg in args) {
            value [argPreamble,argVariable] = arg.assigned;
            preamble += argPreamble + "\n";
            instructed = instructed.replace("{}", argVariable);
        }

        return preamble + instructed;
    }

    shared default [String,String] assigned {
        value var = "%_``newTemporaryID()``";
        return [apply("``var`` = "), var];
    }

    shared actual String string => apply();
}

abstract class LLVMLiteral() extends LLVMExpression() {
    shared actual [String,String] assigned => ["", string];
}

"A compilation unit"
class LLVMCompilationUnit(shared actual String containerName,
        shared Boolean inRoot,
        Code[] defs)
    extends Code(defs) {

    value allocations = HashMap<String,[Allocation,Code?]>();

    shared actual Allocation newAllocation(String shortName, Code? definition) {
        if (exists h = allocations[shortName]) { return h.first; }
        value ret = super.newAllocation(shortName, definition);
        value def = definition?.string else "null";
        allocations.put(shortName, [ret, definition]);
        return ret;
    }

    shared actual String string {
        variable String result = "declare i64* @print(i64*)
                                  define private i64* @cMS4xLjE.ceylon.language.print\
                                  (i64* %val) {
                                      %r = call i64* @print(i64* %val)
                                      ret i64* %r
                                  }\n\n";

        result += stringTable;

        if (exists e = runMethod, inRoot) {
            result += "@ceylon_run = alias i64*()* @``e.name``\n\n";
        }

        for (shortName->[alloc, defMaybe] in allocations) {
            value def = defMaybe else "null";
            result
                += "@``containerName``.``shortName`` = global i64* ``def``\n";
        }

        if (!allocations.empty) { result += "\n"; }

        for (child in children) {
            result += "``child``\n";
        }

        result = result.trimTrailing(Character.whitespace) + "\n";

        return result;
    }
}

LLVMCompilationUnit llvmCompilationUnit(String containerName,
        Boolean inRoot,
        Code[] defs) {
    value ret = LLVMCompilationUnit(containerName, inRoot, defs);
    ret.init();
    return ret;
}

"A method definition"
class LLVMMethodDef(String shortName, String[] arguments, Code[] body)
    extends Code(body) {

    "Pool of temporary IDs"
    variable Integer ids = 0;
    shared actual Integer newTemporaryID() => ids++;

    shared actual LLVMMethodDef? runMethod
        => if (shortName == "run") then this else null;

    shared actual String string {
        variable value ret = "define i64* @``name``(";
        value fullArgs = if (contained)
            then arguments.withLeading("this")
            else arguments;

        ret += ", ".join(fullArgs.map((x) => "i64* %``x``"));
        ret += ") {\n";

        for (b in body) {
            value bIndent = b.string
                .replace("\n", "\n    ")
                .trimTrailing(Character.whitespace);
            ret += "    ``bIndent``\n";
        }

        ret += "    ret i64* null\n}\n";
        return ret;
    }

    "Full qualified name of this method"
    shared String name => "``containerName``.``shortName``";
}

LLVMMethodDef llvmMethodDef(String shortName,
        String[] arguments, Code[] body) {
    value ret = LLVMMethodDef(shortName, arguments, body);
    ret.init();
    return ret;
}

"A string literal"
class LLVMStringLiteral(String text)
        extends LLVMLiteral() {
    shared actual String template => "@.str``getStringID(text)``";
    shared actual void onReparent() { getStringID(text); }
}

LLVMStringLiteral llvmStringLiteral(String text) {
    value ret = LLVMStringLiteral(text);
    ret.init();
    return ret;
}

"An invocation"
class LLVMInvocation(String qualifiedName, LLVMExpression[] args)
        extends LLVMExpression(args) {
    value argList = ", ".join({"i64* {}"}.repeat(args.size));
    shared actual String template => "call i64* @``qualifiedName``(``argList``)";
}

LLVMInvocation llvmInvocation(String qualifiedName, LLVMExpression[] args) {
    value ret = LLVMInvocation(qualifiedName, args);
    ret.init();
    return ret;
}

class LLVMValueDefinition(String shortName, Code definition)
        extends Code([definition]) {
    "Backing for allocation member"
    variable Allocation? _allocation = null;

    "The memory allocation backing this definition"
    shared Allocation allocation {
        if (exists a = _allocation) { return a; }
        _allocation = newAllocation(shortName, definition);
        assert(exists a = _allocation);
        return a;
    }

    shared actual void onReparent() {
        _allocation = newAllocation(shortName, definition);
        definition.onReparent();
    }

    shared LLVMMethodDef getter {
        value ret = llvmMethodDef("``shortName``$get", [],
                [llvmReturn(allocation.load)]);
        ret.parent = this;
        return ret;
    }

    shared actual String string => getter.string;
}

LLVMValueDefinition llvmValueDefinition(String shortName, Code definition) {
    value ret = LLVMValueDefinition(shortName, definition);
    ret.init();
    return ret;
}

class LLVMVariableUsage(String qualifiedName)
        extends LLVMExpression() {
    shared actual String template => "call i64* @``qualifiedName``$get()";
}

LLVMVariableUsage llvmVariableUsage(String qualifiedName) {
    value ret = LLVMVariableUsage(qualifiedName);
    ret.init();
    return ret;
}

class LLVMClass(String name, Code[] decls) extends Code(decls) {
    shared actual Boolean contained = true;

    "Next word we can allocate in this class"
    variable Integer nextWord = 1;

    "Allocation list"
    value allocations = HashMap<String,Allocation>();

    shared actual String containerName
        => (parent?.containerName else "") + ".$``name``";

    "Our type info struct"
    value typeInfo => "@``containerName``$typeInfo = global i64 0";
    shared actual String string => typeInfo + "\n\n" +
        super.string.trimTrailing(Character.whitespace) + "\n";

    shared actual Allocation newAllocation(String shortName, Code? definition) {
        if (exists a = allocations[shortName]) { return a; }

        value myWord = nextWord++;
        object gep extends LLVMExpression() {
            shared actual String template
                = "getelementptr i64* %this, i64 ``myWord``";
        }

        gep.init();

        value ret = object satisfies Allocation {
            shared actual LLVMExpression load {
                object expr extends LLVMExpression([gep]) {
                    shared actual String template = "load i64* {}";
                }
                expr.init();

                object expr2 extends LLVMExpression([expr]) {
                    shared actual String template = "inttoptr i64 {} to i64*";
                }
                expr2.init();

                return expr2;
            }

            shared actual String store(Code val) => "";
        };

        allocations.put(shortName, ret);

        return ret;
    }
}

LLVMClass llvmClass(String name, Code[] decls) {
    value ret = LLVMClass(name, decls);
    ret.init();
    return ret;
}

class LLVMReturn(LLVMExpression val) extends LLVMExpression([val]) {
    shared actual String template = "ret i64* {}";
}

LLVMReturn llvmReturn(LLVMExpression val) {
    value ret = LLVMReturn(val);
    ret.init();
    return ret;
}

object llvmNull extends LLVMLiteral() {
    shared actual String template => "null";
}
