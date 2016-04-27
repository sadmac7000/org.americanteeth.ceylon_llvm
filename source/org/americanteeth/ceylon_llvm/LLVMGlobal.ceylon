"An LLVM global variable declaration."
class LLVMGlobal<out T>(String n, LLVMValue<T> startValue, String modifiers =
        "")
        extends LLVMDeclaration(n)
        given T satisfies LLVMType {
    string => "@``name`` = ``modifiers`` global ``startValue``";
}

"Alias supertype of all globals"
alias AnyLLVMGlobal => LLVMGlobal<LLVMType>;
