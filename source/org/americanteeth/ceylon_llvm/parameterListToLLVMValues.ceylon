import ceylon.interop.java {
    CeylonList
}

import org.eclipse.ceylon.model.typechecker.model {
    ParameterList
}

"Convert a parameter list to a sequence of LLVM values"
[AnyLLVMValue*] parameterListToLLVMValues(ParameterList? parameterList)
        => if (exists parameterList)
           then CeylonList(parameterList.parameters)
                        .collect((x) => loc(ptr(i64), x.name))
           else [];
