"Any top-level declaration in an LLVM compilation unit."
abstract class LLVMDeclaration(shared String name) {
    shared default {<String->LLVMType>*} declarationsNeeded = {};
}
