import ceylon.collection { ArrayList, IdentityMap }

class LLVMVariableCache() {
    variable Integer next = 0;
    value map = IdentityMap<LLVMVariable,Integer>();

    shared String get(LLVMVariable l) {
        if (map.defines(l)) {
            assert(exists ret = map[l]);
            return "%_``ret``";
        }

        map.put(l, next);
        return "%_``next++``";
    }
}

class LLVMVariable() {}

class LLVMExpression([String|LLVMVariable|LLVMExpression +] input) {
    value processed = ArrayList<String|LLVMVariable>();
    value preamble = ArrayList<LLVMExpression>();

    for (i in input) {
        if (is String|LLVMVariable i) {
            processed.add(i);
        } else if (is ConstantLLVMExpression i) {
            processed.add(i.string);
        } else {
            value expr = i.assigning;
            preamble.addAll(expr.preamble);
            preamble.add(expr);
            processed.add(expr.output);
        }
    }

    shared default [String|LLVMVariable*] stream = [ for (x in preamble)
        x.stream.withTrailing("\n") ].fold<[String|LLVMVariable*]>([])((x,y) =>
                x.append(y)).append(processed.sequence());

    shared default AssigningLLVMExpression assigning => AssigningLLVMExpression(input);

    shared actual default String string {
        variable String ret = "";
        value cache = LLVMVariableCache();

        for (i in stream) {
            if (is LLVMVariable i) {
                ret += cache.get(i);
            } else {
                ret += i;
            }
        }

        return ret;
    }
}

class AssigningLLVMExpression([String|LLVMVariable|LLVMExpression +] input,
        shared LLVMVariable output = LLVMVariable())
        extends LLVMExpression([output, " = ", *input]) {
    shared actual AssigningLLVMExpression assigning => this;
}

class ConstantLLVMExpression(String expr)
    extends LLVMExpression([expr]) {
    shared actual [String|LLVMVariable *] stream = [expr];
    shared actual String string = "``expr``\n";
}
