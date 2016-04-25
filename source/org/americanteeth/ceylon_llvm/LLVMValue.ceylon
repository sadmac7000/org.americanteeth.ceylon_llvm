"An LLVM typed value"
abstract class LLVMValue<out T>(shared T type) 
        given T satisfies LLVMType {
    shared formal String identifier;
    shared String typeName = type.name;
    string => "``typeName`` ``identifier``";
}

"Alias supertype of all values"
alias AnyLLVMValue => LLVMValue<LLVMType>;

"An LLVM pointer value"
abstract class Ptr<out T>(PtrType<T> t) given T satisfies LLVMType
    => LLVMValue<PtrType<T>>(t);

"An LLVM Function"
abstract class Func<out Ret,in Args>(FuncType<Ret,Args> f)
        given Args satisfies [LLVMType*]
    => LLVMValue<FuncType<Ret,Args>>(f);

"An LLVM 64-bit integer value"
abstract class I64(I64Type t)
    => LLVMValue<I64Type>(t);

"A literal LLVM i64"
final class I64Lit(Integer val) extends I64(i64) {
    identifier = val.string;
}

"An LLVM 32-bit integer value"
abstract class I32(I32Type t)
    => LLVMValue<I32Type>(t);

"A literal LLVM i32"
final class I32Lit(Integer val) extends I32(i32) {
    identifier = val.string;
}

"An LLVM 1-bit integer value"
abstract class I1(I1Type t)
    => LLVMValue<I1Type>(t);

"A literal LLVM i1"
final class I1Lit(Integer val) extends I1(i1) {
    identifier = val.string;
}

"An LLVM Null value"
object llvmNull extends Ptr<I64Type>(ptr(i64)) {
    identifier = "null";
}

"Constructor for LLVM values"
LLVMValue<T> val<T>(T t, String ident)
        given T satisfies LLVMType
    => object extends LLVMValue<T>(t) {
        identifier = ident;
    };
