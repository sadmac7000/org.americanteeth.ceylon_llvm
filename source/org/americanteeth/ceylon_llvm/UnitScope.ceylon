import ceylon.collection {
    ArrayList
}

import org.eclipse.ceylon.model.typechecker.model {
    DeclarationModel=Declaration,
    FunctionOrValueModel=FunctionOrValue,
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
    value mutators = ArrayList<LLVMDeclaration>();

    shared actual LLVMFunction body
            = LLVMFunction("__ceylon_constructor", null, "private", []);

    shared actual Boolean owns(DeclarationModel d) => d.toplevel;

    LLVMFunction getterFor(ValueModel model) {
        value getter = LLVMFunction(getterName(model), ptr(i64), "", []);
        value ret = getter.loadGlobal(ptr(i64), declarationName(model));
        getter.ret(ret);
        return getter;
    }

    LLVMFunction setterFor(ValueModel model) {
        value setter = LLVMFunction(setterName(model), ptr(i64), "",
                [loc(ptr(i64), ".value")]);
        value valueReg = setter.register(ptr(i64), ".value");
        setter.storeGlobal(declarationName(model), valueReg);
        return setter;
    }

    shared actual void allocate(FunctionOrValueModel declaration,
        Ptr<I64Type>? startValue) {
        "Functions shouldn't be allocated as variables at the top level"
        assert(is ValueModel declaration);

        value name = declarationName(declaration);

        globalVariables.add(LLVMGlobal(name, llvmNull));
        mutators.add(getterFor(declaration));

        if (declaration.\ivariable) {
            mutators.add(setterFor(declaration));
            if (exists startValue) {
                body.call(ptr(i64), setterName(declaration), startValue);
            }
        } else if (exists startValue){
            body.storeGlobal(declarationName(declaration), startValue);
        }
    }

    shared actual {LLVMDeclaration*} results {
        value superResults = super.results;

        assert (is LLVMFunction s = superResults.first);
        s.makeConstructor(toplevelConstructorPriority);

        return globalVariables.chain(superResults).chain(mutators);
    }
}
