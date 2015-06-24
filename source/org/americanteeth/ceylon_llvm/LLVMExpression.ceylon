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
        } else {
            value expr = i.assigning;
            preamble.addAll(expr.preamble);
            preamble.add(expr);
            processed.add(i.output);
        }
    }

    shared [String|LLVMVariable*] stream = [ for (x in preamble)
        x.stream.withTrailing("\n") ].fold<[String|LLVMVariable*]>([])((x,y) =>
                x.append(y)).append(processed.sequence());

    shared default AssigningLLVMExpression assigning => AssigningLLVMExpression(input);

    shared LLVMVariable output {
        assert(this is AssigningLLVMExpression);
        assert(is LLVMVariable i = input.first);
        return i;
    }

    shared actual String string {
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

class AssigningLLVMExpression([String|LLVMVariable|LLVMExpression +] input)
        extends LLVMExpression([LLVMVariable(), " = ", *input]) {
    shared actual AssigningLLVMExpression assigning => this;
}
