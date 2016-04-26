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

"An LLVM Function type"
class FuncType<out Ret,in Args>(shared Ret&LLVMType? returnType, Args args)
        extends LLVMType("``returnType else "void"``(``",".join(args)``)")
        given Args satisfies [LLVMType*] {
    shared [LLVMType*] argumentTypes = args;
}

"Alias supertype of all LLVM Function types"
alias AnyLLVMFunctionType => FuncType<Anything,Nothing>;

"Abbreviated constructor for pointer types"
PtrType<T> ptr<T>(T targetType) given T satisfies LLVMType
    => PtrType<T>(targetType);

"An LLVM Integer type"
abstract class IntegerType(Integer bits) extends LLVMType("i``bits``") {}

"i64 LLVM type base class"
abstract class I64Type() of i64 extends IntegerType(64) {}

"i64 LLVM type instance"
object i64 extends I64Type() {}

"i32 LLVM type base class"
abstract class I32Type() of i32 extends IntegerType(32) {}

"i32 LLVM type instance"
object i32 extends I32Type() {}

"i1 LLVM type base class"
abstract class I1Type() of i1 extends IntegerType(1) {}

"i1 LLVM type instance"
object i1 extends I1Type() {}
