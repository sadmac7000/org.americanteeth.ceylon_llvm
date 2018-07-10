import ceylon.collection {
    ArrayList
}

import org.eclipse.ceylon.model.typechecker.model {
    FunctionModel=Function,
    ValueModel=Value,
    InterfaceModel=Interface,
    DeclarationModel=Declaration
}

"Scope of an interface."
class InterfaceScope(LLVMModule mod, InterfaceModel model,
            Anything(Scope) destroyer)
        extends Scope(mod, null, destroyer) {
    shared actual Boolean owns(DeclarationModel d)
        => if (exists c = d.container, c == model) then true else false;

    shared actual {LLVMDeclaration*} results {
        value setup = llvmFunction(llvmModule, setupName(model), null,
                [ptr(i64)]);
        assert(is LLVMValue<PtrType<I64Type>> vtable = setup.arguments.first);
        value results = ArrayList<LLVMDeclaration>{setup};
        variable value offset = 0;

        setup.private = true;

        for (member in model.members) {
            if (member.\iactual || !(member.\iformal || member.\idefault)) {
                continue;
            }

            value memberOffset = offset++;

            if (is FunctionModel member) {
                value argTypes =
                    parameterListToLLVMTypes(member.firstParameterList)
                        .withTrailing(ptr(i64));
                value funcType = FuncType(ptr(i64), argTypes);
                value func = setup.global(funcType, dispatchName(member));
                setup.store(vtable, setup.toI64(func), I64Lit(memberOffset));
            } else {
                "TODO: Support classes etc."
                assert(is ValueModel member);
                value getterType = FuncType(ptr(i64), [ptr(i64)]);
                value getter = setup.global(getterType,
                        getterDispatchName(member));
                setup.store(vtable, setup.toI64(getter), I64Lit(memberOffset));

                if (member.\ivariable) {
                    value setterOffset = offset++;
                    value setterType = FuncType(ptr(i64),
                            [ptr(i64), ptr(i64)]);
                    value setter = setup.global(setterType,
                            setterDispatchName(member));
                    setup.store(vtable, setup.toI64(setter),
                            I64Lit(setterOffset));
                }
            }

            results.add(LLVMGlobal(vtPositionName(member),
                        I64Lit(memberOffset)));
        }

        results.add(LLVMGlobal(vtSizeName(model), I64Lit(offset)));

        return results;
    }
}
