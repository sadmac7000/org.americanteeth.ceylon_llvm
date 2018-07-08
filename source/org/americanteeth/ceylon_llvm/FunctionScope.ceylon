import org.eclipse.ceylon.model.typechecker.model {
    FunctionModel=Function
}

"Construct an LLVM function with the approprate signature for a given Ceylon
 function."
LLVMFunction llvmFunctionForCeylonFunction(LLVMModule mod, FunctionModel model,
        String(FunctionModel) namer = declarationName)
    => LLVMFunction(mod, namer(model), ptr(i64), "",
                if (!model.toplevel)
                then [loc(ptr(i64), ".context"),
                    *parameterListToLLVMValues(model.firstParameterList)]
                else parameterListToLLVMValues(model.firstParameterList));

"The scope of a function"
class FunctionScope(LLVMModule mod, FunctionModel model,
            Anything(Scope) destroyer)
        extends CallableScope(mod, model, dispatchName, destroyer) {
    shared actual LLVMFunction body =
        llvmFunctionForCeylonFunction(mod, model, dispatchName);
}
