import org.bytedeco.javacpp {
    LLVM { LLVMValueRef }
}

"An LLVM typed value"
abstract class LLVMValue<out T>(shared T type, shared LLVMValueRef ref)
        given T satisfies LLVMType {
    shared formal String identifier;
    shared String typeName = type.name;
    string => "``typeName`` ``identifier``";
    hash => string.hash;

    shared actual Boolean equals(Object other)
            => other is AnyLLVMValue && other.string==string;
}

"Alias supertype of all values"
abstract class AnyLLVMValue(LLVMType t, LLVMValueRef r)
    => LLVMValue<LLVMType>(t, r);

"An LLVM pointer value"
abstract class Ptr<out T>(PtrType<T> t, LLVMValueRef r)
        given T satisfies LLVMType
    => LLVMValue<PtrType<T>>(t, r);

"An LLVM Function"
abstract class Func<out Ret, in Args>(FuncType<Ret,Args> f, LLVMValueRef r)
        given Args satisfies [LLVMType*]
    => LLVMValue<FuncType<Ret,Args>>(f, r);

"An LLVM label"
abstract class Label(LabelType t, LLVMValueRef r)
    => LLVMValue<LabelType>(t, r);

"An LLVM 64-bit integer value"
abstract class I64(I64Type t, LLVMValueRef r)
    => LLVMValue<I64Type>(t, r);

"A literal LLVM i64"
final class I64Lit(Integer val) extends I64(i64, llvm.constInt(i64.ref, val)) {
    identifier = val.string;
}

"An LLVM 32-bit integer value"
abstract class I32(I32Type t, LLVMValueRef r)
        => LLVMValue<I32Type>(t, r);

"A literal LLVM i32"
final class I32Lit(Integer val) extends I32(i32, llvm.constInt(i32.ref, val)) {
    identifier = val.string;
}

"An LLVM 1-bit integer value"
abstract class I1(I1Type t, LLVMValueRef r)
        => LLVMValue<I1Type>(t, r);

"A literal LLVM i1"
final class I1Lit(Integer val) extends I1(i1, llvm.constInt(i1.ref, val)) {
    identifier = val.string;
}

"An LLVM Null value"
object llvmNull extends Ptr<I64Type>(ptr(i64), llvm.constNull(ptr(i64).ref)) {
    identifier = "null";
}

"Constructor for LLVM 'undef' value"
LLVMValue<T> undef<T>(T t) given T satisfies LLVMType
    => object extends LLVMValue<T>(t, llvm.undef(t.ref)) {
        identifier = "undef";
    };

"Constructor for LLVM local values"
LLVMValue<T> loc<T>(T t, String ident)
        given T satisfies LLVMType
    => object extends LLVMValue<T>(t, llvm.undef(t.ref)) { /* FIXME: Undef */
        identifier = ident;
    };
