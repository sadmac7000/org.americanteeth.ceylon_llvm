import org.eclipse.ceylon.model.typechecker.model {
    FunctionModel=Function
}

"Construct an LLVM function with the approprate signature for a given Ceylon
 function."
LLVMFunction<PtrType<I64Type>,[PtrType<I64Type>*]>
    llvmFunctionForCeylonFunction(LLVMModule mod, FunctionModel model,
        String(FunctionModel) namer = declarationName)
    => LLVMFunction(mod, namer(model), ptr(i64),
                if (!model.toplevel)
                then parameterListToLLVMTypes(model.firstParameterList)
                         .withLeading(ptr(i64))
                else parameterListToLLVMTypes(model.firstParameterList));

"The scope of a function"
class FunctionScope(LLVMModule mod, FunctionModel model,
            Anything(Scope) destroyer)
        extends CallableScope(mod, model, dispatchName, destroyer) {
    shared actual LLVMFunction<PtrType<I64Type>, [PtrType<I64Type>*]> body =
        llvmFunctionForCeylonFunction(mod, model, dispatchName);
}
