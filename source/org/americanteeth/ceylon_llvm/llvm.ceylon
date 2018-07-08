import org.bytedeco.javacpp {
    LLVM {
        llvmInitializeNativeAsmPrinter=\iLLVMInitializeNativeAsmPrinter,
        llvmInitializeNativeAsmParser=\iLLVMInitializeNativeAsmParser,
        llvmInitializeNativeDisassembler=\iLLVMInitializeNativeDisassembler,
        llvmInitializeNativeTarget=\iLLVMInitializeNativeTarget,

        LLVMModuleRef,
        llvmModuleCreateWithName=\iLLVMModuleCreateWithName,
        llvmPrintModuleToString=\iLLVMPrintModuleToString,
        llvmGetTarget=\iLLVMGetTarget,
        llvmSetTarget=\iLLVMSetTarget,
        llvmGetDefaultTargetTriple=\iLLVMGetDefaultTargetTriple,
        llvmDisposeModule=\iLLVMDisposeModule,

        LLVMTypeRef,
        llvmInt32Type=\iLLVMInt32Type,
        llvmInt64Type=\iLLVMInt64Type,
        llvmIntType=\iLLVMIntType,
        llvmPointerType=\iLLVMPointerType,
        llvmFunctionType=\iLLVMFunctionType,
        llvmStructType=\iLLVMStructType,
        llvmVoidType=\iLLVMVoidType,
        llvmLabelType=\iLLVMLabelType,

        LLVMValueRef,
        llvmConstInt=\iLLVMConstInt,
        llvmConstNull=\iLLVMConstNull,
        llvmGetUndef=\iLLVMGetUndef,

        llvmWriteBitcodeToFile=\iLLVMWriteBitcodeToFile
    }
}
import ceylon.interop.java { createJavaObjectArray }

object llvmLibrary {
    variable value initialized = false;

    shared void initialize() {
        if (initialized) {
            return;
        }

        llvmInitializeNativeAsmPrinter();
        llvmInitializeNativeAsmParser();
        llvmInitializeNativeDisassembler();
        llvmInitializeNativeTarget();
    }

    shared LLVMTypeRef int64Type()
        => llvmInt64Type();
    shared LLVMTypeRef pointerType(LLVMTypeRef t)
        => llvmPointerType(t, 0); // The 0 should be a constant value
    shared LLVMTypeRef functionType(LLVMTypeRef? ret, [LLVMTypeRef*] args)
        => llvmFunctionType(ret else llvmVoidType(),
                createJavaObjectArray(args)[0], args.size, 0 /* false */);
    shared LLVMTypeRef structType([LLVMTypeRef*] items)
        => llvmStructType(createJavaObjectArray(items)[0], items.size,
                0 /* false */);

    shared LLVMTypeRef labelType => llvmLabelType();
    shared LLVMTypeRef i64Type => llvmInt64Type();
    shared LLVMTypeRef i32Type => llvmInt32Type();
    shared LLVMTypeRef intType(Integer bits) => llvmIntType(bits);

    shared String printModuleToString(LLVMModuleRef ref)
        => llvmPrintModuleToString(ref).getString();

    shared String getTarget(LLVMModuleRef ref)
        => llvmGetTarget(ref).getString();
    shared void setTarget(LLVMModuleRef ref, String target)
        => llvmSetTarget(ref, target);
    shared String defaultTarget
        => llvmGetDefaultTargetTriple().getString();

    shared LLVMModuleRef moduleCreateWithName(String name)
        => llvmModuleCreateWithName(name);
    shared void disposeModule(LLVMModuleRef ref)
        => llvmDisposeModule(ref);

    shared LLVMValueRef constInt(LLVMTypeRef t, Integer val)
        => llvmConstInt(t, val, 1 /* sign extend: true */);
    shared LLVMValueRef constNull(LLVMTypeRef t) => llvmConstNull(t);
    shared LLVMValueRef undef(LLVMTypeRef t) => llvmGetUndef(t);

    shared void writeBitcodeToFile(LLVMModuleRef ref, String path)
        => llvmWriteBitcodeToFile(ref, path);
}

class LLVMModule satisfies Destroyable {
    LLVMModuleRef ref;

    shared new withName(String name) {
        ref = llvm.moduleCreateWithName(name);
        llvm.setTarget(ref, llvm.defaultTarget);
    }

    shared actual void destroy(Throwable? error) {
        llvm.disposeModule(ref);
    }

    shared String target => llvm.getTarget(ref);
    assign target => llvm.setTarget(ref, target);

    shared void writeBitcodeFile(String path)
        => llvm.writeBitcodeToFile(ref, path);

    string => llvm.printModuleToString(ref);
}

\IllvmLibrary llvm {
    llvmLibrary.initialize();
    return llvmLibrary;
}

