import org.bytedeco.javacpp {
    LLVM { LLVMValueRef }
}

"An LLVM typed value"
class LLVMValue<out T>(shared T type, shared LLVMValueRef ref)
        given T satisfies LLVMType {
    string => llvm.printValueToString(ref);
    hash => string.hash;

    shared actual Boolean equals(Object other)
            => other is AnyLLVMValue && other.string==string;
}

"Alias supertype of all values"
class AnyLLVMValue(LLVMType t, LLVMValueRef r)
    => LLVMValue<LLVMType>(t, r);

"An LLVM pointer value"
class Ptr<out T>(PtrType<T> t, LLVMValueRef r)
        given T satisfies LLVMType
    => LLVMValue<PtrType<T>>(t, r);

"An LLVM Function"
class Func<out Ret, in Args>(FuncType<Ret,Args> f, LLVMValueRef r)
        given Args satisfies [LLVMType*]
    => LLVMValue<FuncType<Ret,Args>>(f, r);

"An LLVM label"
class Label(LabelType t, LLVMValueRef r)
    => LLVMValue<LabelType>(t, r);

"An LLVM 64-bit integer value"
class I64(I64Type t, LLVMValueRef r)
    => LLVMValue<I64Type>(t, r);

"A literal LLVM i64"
final class I64Lit(Integer val) extends I64(i64, llvm.constInt(i64.ref, val)) {}

"An LLVM 32-bit integer value"
class I32(I32Type t, LLVMValueRef r) => LLVMValue<I32Type>(t, r);

"A literal LLVM i32"
final class I32Lit(Integer val) extends I32(i32, llvm.constInt(i32.ref, val)) {}

"An LLVM 8-bit integer value"
class I8(I8Type t, LLVMValueRef r) => LLVMValue<I8Type>(t, r);

"A literal LLVM i8"
final class I8Lit(Integer|Byte val) extends I8(i8, llvm.constInt(i8.ref,
            if (is Integer val) then val else val.unsigned)) {}

"An LLVM 1-bit integer value"
class I1(I1Type t, LLVMValueRef r) => LLVMValue<I1Type>(t, r);

"A literal LLVM i1"
final class I1Lit(Integer val) extends I1(i1, llvm.constInt(i1.ref, val)) {}

"An LLVM Null value"
Ptr<I64Type> llvmNull = ptr(i64).instance(llvm.constNull(ptr(i64).ref));

"Constructor for LLVM 'undef' value"
LLVMValue<T> undef<T>(T t) given T satisfies LLVMType
    => LLVMValue(t, llvm.undef(t.ref));

"Constructor for constant arrays"
LLVMValue<ArrayType<T>> constArray<T>(T ty, [LLVMValue<T>*] elements)
        given T satisfies LLVMType
    => ArrayType<T>(ty, elements.size).instance(
            llvm.constArray(ty.ref, elements.collect((x) => x.ref)));

"Interface for global values"
class LLVMGlobalValue<T>(T ty, LLVMValueRef r)
        extends LLVMValue<T>(ty, r)
        given T satisfies LLVMType {
    "Whether this is a constant value"
    shared Boolean constant => llvm.isGlobalConstant(ref);
    assign constant {
        llvm.setGlobalConstant(ref, constant);
    }

    "Initial value for this variable"
    shared LLVMValue<T> initializer
        => LLVMValue(type, llvm.getInitializer(ref));
    assign initializer {
        llvm.setInitializer(ref, initializer.ref);
    }

    "What section this variable will be placed in"
    shared String section => llvm.getSection(ref);
    assign section {
        llvm.setSection(ref, section);
    }

    "Alignment of this value"
    shared Integer alignment => llvm.getAlignment(ref);
    assign alignment {
        llvm.setAlignment(ref, alignment);
    }
}
