"An LLVM global variable declaration."
class LLVMGlobal<out T>(shared actual String name, LLVMValue<T> startValue, String modifiers =
        "")
        satisfies LLVMDeclaration
        given T satisfies LLVMType {
    declarationsNeeded = {};
    string => "@``name`` = ``modifiers`` global ``startValue``";
}

"Alias supertype of all globals"
alias AnyLLVMGlobal => LLVMGlobal<LLVMType>;
