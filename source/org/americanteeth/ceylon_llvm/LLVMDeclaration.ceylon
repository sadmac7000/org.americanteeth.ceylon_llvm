"Any top-level declaration in an LLVM compilation unit."
interface LLVMDeclaration {
    shared formal String name;
    shared formal {<String->LLVMType>*} declarationsNeeded;
}
