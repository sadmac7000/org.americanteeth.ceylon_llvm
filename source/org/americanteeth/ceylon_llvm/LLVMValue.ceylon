import org.bytedeco.javacpp {
    LLVM { LLVMValueRef }
}

interface ValueInterface<out T>
        given T satisfies LLVMType {
    shared formal T type;
    shared formal LLVMValueRef ref;
}

"An LLVM typed value"
abstract class LLVMValue<out T>(shared actual T type,
                                shared actual LLVMValueRef ref)
        satisfies ValueInterface<T>
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

"An LLVM 8-bit integer value"
abstract class I8(I8Type t, LLVMValueRef r)
        => LLVMValue<I8Type>(t, r);

"A literal LLVM i8"
final class I8Lit(Integer|Byte val) extends I8(i8, llvm.constInt(i8.ref,
            if (is Integer val) then val else val.unsigned)) {
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

"Constructor for constant arrays"
LLVMValue<ArrayType<T>> constArray<T>(T ty, [LLVMValue<T>*] elements)
        given T satisfies LLVMType
    => object extends LLVMValue<ArrayType<T>>(ArrayType<T>(ty, elements.size),
            llvm.constArray(ty.ref, elements.collect((x) => x.ref))) {
        identifier = "[``", ".join(elements)``]";
    };

"Interface for global values"
interface LLVMGlobalValue<T>
        satisfies ValueInterface<T>
        given T satisfies LLVMType {
    "Whether this is a constant value"
    shared Boolean constant => llvm.isGlobalConstant(ref);
    assign constant {
        llvm.setGlobalConstant(ref, constant);
    }

    "Initial value for this variable"
    shared LLVMValue<T> initializer
        => object extends LLVMValue<T>(outer.type, llvm.getInitializer(outer.ref)) {
            identifier = "<constant>";
        };
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
