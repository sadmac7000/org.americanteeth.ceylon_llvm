import org.bytedeco.javacpp {
    LLVM { LLVMTypeRef }
}

"An LLVM type"
abstract class LLVMType(shared String name, shared LLVMTypeRef ref) {
    string = name;
    hash = string.hash;

    shared actual Boolean equals(Object other) {
        return other is LLVMType && other.string==string;
    }
}

"An LLVM Pointer type"
class PtrType<out T>(shared T targetType)
        extends LLVMType("``targetType``*", llvm.pointerType(targetType.ref))
        given T satisfies LLVMType {}

"Alias supertype of all LLVM Pointer types"
alias AnyLLVMPointerType => PtrType<LLVMType>;

"An LLVM Function type"
class FuncType<out Ret, in Args>(shared Ret&LLVMType? returnType, Args args)
        extends LLVMType("`` returnType else "void" ``(``",".join(args)``)",
                        llvm.functionType(returnType?.ref,
                            args.collect((x) => x.ref)))
        given Args satisfies [LLVMType*] {
    shared [LLVMType*] argumentTypes = args;
}

"Alias supertype of all LLVM Function types"
alias AnyLLVMFunctionType => FuncType<Anything,Nothing>;

"LLVM Label type base class"
abstract class LabelType() of label extends LLVMType("label", llvm.labelType) {}

"LLVM Label type instance"
object label extends LabelType() {}

"Abbreviated constructor for pointer types"
PtrType<T> ptr<T>(T targetType) given T satisfies LLVMType
        => PtrType<T>(targetType);

"An LLVM Integer type"
abstract class IntegerType(Integer bits, LLVMTypeRef? ref = null)
        extends LLVMType("i``bits``", ref else llvm.intType(bits)) {}

"i64 LLVM type base class"
abstract class I64Type() of i64 extends IntegerType(64, llvm.i64Type) {}

"i64 LLVM type instance"
object i64 extends I64Type() {}

"i32 LLVM type base class"
abstract class I32Type() of i32 extends IntegerType(32, llvm.i32Type) {}

"i32 LLVM type instance"
object i32 extends I32Type() {}

"i1 LLVM type base class"
abstract class I1Type() of i1 extends IntegerType(1) {}

"i1 LLVM type instance"
object i1 extends I1Type() {}
