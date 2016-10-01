import ceylon.collection {
    ArrayList
}

import com.redhat.ceylon.model.typechecker.model {
    FunctionModel=Function,
    InterfaceModel=Interface
}

"Scope of an interface."
class InterfaceScope(InterfaceModel model) extends Scope() {
    shared actual Nothing body {
        "Interfaces are not backed by a function body."
        assert(false);
    }

    shared actual {LLVMDeclaration*} results {
        value setup = LLVMFunction(setupName(model), null, "private",
                [loc(ptr(i64), ".vtable")]);
        value vtable = setup.register(ptr(i64), ".vtable");
        value results = ArrayList<LLVMDeclaration>{setup};
        variable value offset = 0;

        for (member in model.members) {
            if (member.\iactual || !(member.\iformal || member.\idefault)) {
                continue;
            }

            value memberOffset = offset++;

            /*TODO:*/
            "We only support functions in vtables at this time."
            assert(is FunctionModel member);

            value argTypes =
                parameterListToLLVMValues(member.firstParameterList)
                    .map((x) => x.type)
                    .follow(ptr(i64))
                    .sequence();
            value funcType = FuncType(ptr(i64), argTypes);
            value func = setup.global(funcType, dispatchName(member));
            setup.store(vtable, setup.toI64(func), I64Lit(memberOffset));

            results.add(LLVMGlobal(vtPositionName(member),
                        I64Lit(memberOffset)));
        }

        results.add(LLVMGlobal(vtSizeName(model), I64Lit(offset)));

        return results;
    }
}
