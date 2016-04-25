"An LLVM type"
abstract class LLVMType(shared String name) {
    string = name;
}

"An LLVM Pointer type"
class PtrType<out T>(shared T targetType)
        extends LLVMType("``targetType.name``*")
        given T satisfies LLVMType {}

"Alias supertype of all LLVM Pointer types"
alias AnyLLVMPointerType => PtrType<LLVMType>;

"Abbreviated constructor for pointer types"
PtrType<T> ptr<T>(T targetType) given T satisfies LLVMType
    => PtrType<T>(targetType);

"i64 LLVM type base class"
abstract class I64Type() of i64 extends LLVMType("i64") {}

"i64 LLVM type instance"
object i64 extends I64Type() {}

"i32 LLVM type base class"
abstract class I32Type() of i32 extends LLVMType("i32") {}

"i32 LLVM type instance"
object i32 extends I32Type() {}

"i1 LLVM type base class"
abstract class I1Type() of i1 extends LLVMType("i1") {}

"i1 LLVM type instance"
object i1 extends I1Type() {}
