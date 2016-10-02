import ceylon.collection {
    ArrayList
}

import com.redhat.ceylon.model.typechecker.model {
    ValueModel=Value
}

"Priority of the library constructor function that contains all of the toplevel
 code. Maximum inheritance depth is effectively bounded by this value, as
 vtable initializers are expected to have values equal to the declared item's
 inheritance depth."
Integer toplevelConstructorPriority = constructorPriorityOffset + 65535;

"The outermost scope of the compilation unit"
class UnitScope() extends Scope((Anything x) => null) {
    value globalVariables = ArrayList<AnyLLVMGlobal>();
    value getters = ArrayList<LLVMDeclaration>();

    shared actual LLVMFunction body
            = LLVMFunction("__ceylon_constructor", null, "private", []);

    LLVMFunction getterFor(ValueModel model) {
        value getter = LLVMFunction(getterName(model), ptr(i64), "", []);
        value ret = getter.load(getter.global(ptr(i64),
                declarationName(model)));
        getter.ret(ret);
        return getter;
    }

    shared actual void allocate(ValueModel declaration,
        Ptr<I64Type>? startValue) {
        value name = declarationName(declaration);

        globalVariables.add(LLVMGlobal(name, startValue else llvmNull));
        getters.add(getterFor(declaration));
    }

    shared actual {LLVMDeclaration*} results {
        value superResults = super.results;

        assert (is LLVMFunction s = superResults.first);
        s.makeConstructor(toplevelConstructorPriority);

        return globalVariables.chain(superResults).chain(getters);
    }
}
