import com.redhat.ceylon.model.typechecker.model {
    FunctionModel=Function
}

"Marker to indicate a function is the non-dispatching call-point."
String dispatchTag(FunctionModel model)
    => if (model.\idefault) then "$noDispatch" else "";

"Construct an LLVM function with the approprate signature for a given Ceylon
 function."
LLVMFunction llvmFunctionForCeylonFunction(FunctionModel model, String tag = "")
    => LLVMFunction(declarationName(model) + tag, ptr(i64), "",
                if (!model.toplevel)
                then [val(ptr(i64), "%.context"),
                    *parameterListToLLVMValues(model.firstParameterList)]
                else parameterListToLLVMValues(model.firstParameterList));

"The scope of a function"
class FunctionScope(FunctionModel model)
        extends CallableScope(model, dispatchTag(model)) {
    shared actual LLVMFunction body =
        llvmFunctionForCeylonFunction(model, dispatchTag(model));
}
