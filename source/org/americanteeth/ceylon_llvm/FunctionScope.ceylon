import com.redhat.ceylon.model.typechecker.model {
    FunctionModel=Function
}

"Construct an LLVM function with the approprate signature for a given Ceylon
 function."
LLVMFunction llvmFunctionForCeylonFunction(FunctionModel model,
        String(FunctionModel) namer = declarationName)
    => LLVMFunction(namer(model), ptr(i64), "",
                if (!model.toplevel)
                then [loc(ptr(i64), ".context"),
                    *parameterListToLLVMValues(model.firstParameterList)]
                else parameterListToLLVMValues(model.firstParameterList));

"The scope of a function"
class FunctionScope(FunctionModel model)
        extends CallableScope(model, dispatchName) {
    shared actual LLVMFunction body =
        llvmFunctionForCeylonFunction(model, dispatchName);
}
