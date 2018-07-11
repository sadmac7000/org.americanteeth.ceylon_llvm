import org.bytedeco.javacpp {
    LLVM {
        LLVMTypeRef,
        LLVMValueRef
    }
}

"An LLVM type"
abstract class LLVMType(shared LLVMTypeRef ref) {
    string = llvm.printTypeToString(ref);
    hash = string.hash;

    shared default LLVMValue<LLVMType> instance(LLVMValueRef ref)
        => LLVMValue<LLVMType>(this, ref);

    shared actual Boolean equals(Object other)
        => if (is LLVMType other)
           then other.ref==ref
           else false;
}

"An LLVM Pointer type"
class PtrType<out T>(shared T targetType)
        extends LLVMType(llvm.pointerType(targetType.ref))
        given T satisfies LLVMType {
    shared actual LLVMValue<PtrType<T>> instance(LLVMValueRef ref)
        => LLVMValue<PtrType<T>>(this, ref);
}

"Alias supertype of all LLVM Pointer types"
alias AnyLLVMPointerType => PtrType<LLVMType>;

"An LLVM Function type"
class FuncType<out Ret, in Args>(shared Ret&LLVMType? returnType, Args args)
        extends LLVMType(llvm.functionType(returnType?.ref,
                            args.collect((x) => x.ref)))
        given Args satisfies [LLVMType*] {
    shared [LLVMType*] argumentTypes = args;
    shared actual LLVMValue<FuncType<Ret, Args>> instance(LLVMValueRef ref)
        => LLVMValue<FuncType<Ret, Args>>(this, ref);
}

"Alias supertype of all LLVM Function types"
alias AnyLLVMFunctionType => FuncType<Anything,Nothing>;

"Struct type"
class StructType<Items>(shared Items items)
        extends LLVMType(llvm.structType(items.collect((x) => x.ref)))
        given Items satisfies [LLVMType*] {
    shared actual LLVMValue<StructType<Items>> instance(LLVMValueRef ref)
        => LLVMValue<StructType<Items>>(this, ref);
}

"Array type"
class ArrayType<Item>(shared Item item, shared Integer size)
        extends LLVMType(llvm.arrayType(item.ref, size))
        given Item satisfies LLVMType {
    shared actual LLVMValue<ArrayType<Item>> instance(LLVMValueRef ref)
        => LLVMValue<ArrayType<Item>>(this, ref);
}

"LLVM Label type base class"
abstract class LabelType() of labelType extends LLVMType(llvm.labelType) {
    shared actual LLVMValue<LabelType> instance(LLVMValueRef ref)
        => LLVMValue<LabelType>(this, ref);
}

"LLVM Label type instance"
object labelType extends LabelType() {}

"Abbreviated constructor for pointer types"
PtrType<T> ptr<T>(T targetType) given T satisfies LLVMType
        => PtrType<T>(targetType);

"An LLVM Integer type"
abstract class IntegerType(Integer bits, LLVMTypeRef? ref = null)
        extends LLVMType(ref else llvm.intType(bits)) {
    shared actual default LLVMValue<IntegerType> instance(LLVMValueRef ref)
        => LLVMValue<IntegerType>(this, ref);
}

"i64 LLVM type base class"
abstract class I64Type() of i64 extends IntegerType(64, llvm.i64Type) {
    shared actual LLVMValue<I64Type> instance(LLVMValueRef ref)
        => LLVMValue<I64Type>(this, ref);
}

"i64 LLVM type instance"
object i64 extends I64Type() {}

"i32 LLVM type base class"
abstract class I32Type() of i32 extends IntegerType(32, llvm.i32Type) {
    shared actual LLVMValue<I32Type> instance(LLVMValueRef ref)
        => LLVMValue<I32Type>(this, ref);
}

"i32 LLVM type instance"
object i32 extends I32Type() {}

"i8 LLVM type base class"
abstract class I8Type() of i8 extends IntegerType(8, llvm.i8Type) {
    shared actual LLVMValue<I8Type> instance(LLVMValueRef ref)
        => LLVMValue<I8Type>(this, ref);
}

"i8 LLVM type instance"
object i8 extends I8Type() {}

"i1 LLVM type base class"
abstract class I1Type() of i1 extends IntegerType(1) {
    shared actual LLVMValue<I1Type> instance(LLVMValueRef ref)
        => LLVMValue<I1Type>(this, ref);
}

"i1 LLVM type instance"
object i1 extends I1Type() {}
