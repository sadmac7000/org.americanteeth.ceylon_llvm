import org.bytedeco.javacpp {
    LLVM { LLVMTypeRef }
}

"An LLVM type"
abstract class LLVMType(shared LLVMTypeRef ref) {
    string = llvm.printTypeToString(ref);
    hash = string.hash;

    shared actual Boolean equals(Object other) {
        return other is LLVMType && other.string==string;
    }
}

"An LLVM Pointer type"
class PtrType<out T>(shared T targetType)
        extends LLVMType(llvm.pointerType(targetType.ref))
        given T satisfies LLVMType {}

"Alias supertype of all LLVM Pointer types"
alias AnyLLVMPointerType => PtrType<LLVMType>;

"An LLVM Function type"
class FuncType<out Ret, in Args>(shared Ret&LLVMType? returnType, Args args)
        extends LLVMType(llvm.functionType(returnType?.ref,
                            args.collect((x) => x.ref)))
        given Args satisfies [LLVMType*] {
    shared [LLVMType*] argumentTypes = args;
}

"Alias supertype of all LLVM Function types"
alias AnyLLVMFunctionType => FuncType<Anything,Nothing>;

"Struct type"
class StructType<Items>(shared Items items)
        extends LLVMType(llvm.structType(items.collect((x) => x.ref)))
        given Items satisfies [LLVMType*] {}

"Array type"
class ArrayType<Item>(shared Item item, shared Integer size)
        extends LLVMType(llvm.arrayType(item.ref, size))
        given Item satisfies LLVMType {}

"LLVM Label type base class"
abstract class LabelType() of label extends LLVMType(llvm.labelType) {}

"LLVM Label type instance"
object label extends LabelType() {}

"Abbreviated constructor for pointer types"
PtrType<T> ptr<T>(T targetType) given T satisfies LLVMType
        => PtrType<T>(targetType);

"An LLVM Integer type"
abstract class IntegerType(Integer bits, LLVMTypeRef? ref = null)
        extends LLVMType(ref else llvm.intType(bits)) {}

"i64 LLVM type base class"
abstract class I64Type() of i64 extends IntegerType(64, llvm.i64Type) {}

"i64 LLVM type instance"
object i64 extends I64Type() {}

"i32 LLVM type base class"
abstract class I32Type() of i32 extends IntegerType(32, llvm.i32Type) {}

"i32 LLVM type instance"
object i32 extends I32Type() {}

"i8 LLVM type base class"
abstract class I8Type() of i8 extends IntegerType(8, llvm.i8Type) {}

"i8 LLVM type instance"
object i8 extends I8Type() {}

"i1 LLVM type base class"
abstract class I1Type() of i1 extends IntegerType(1) {}

"i1 LLVM type instance"
object i1 extends I1Type() {}
