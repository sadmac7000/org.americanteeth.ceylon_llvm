import com.redhat.ceylon.model.typechecker.model {
    FunctionModel=Function
}

"The scope of a function"
class FunctionScope(FunctionModel model) extends CallableScope(model) {
    shared actual LLVMFunction body
            = LLVMFunction(declarationName(model), ptr(i64), "",
                if (!model.toplevel)
                then [val(ptr(i64), "%.context"),
                        *parameterListToLLVMValues(model.firstParameterList)]
                else parameterListToLLVMValues(model.firstParameterList));
}
