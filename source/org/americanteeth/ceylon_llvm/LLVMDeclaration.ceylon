"Any top-level declaration in an LLVM compilation unit."
interface LLVMDeclaration {
    shared formal String name;
    shared default {<String->LLVMType>*} declarationsNeeded => {};
}
