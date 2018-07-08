import org.bytedeco.javacpp {
    LLVM {
        llvmInitializeNativeAsmPrinter=\iLLVMInitializeNativeAsmPrinter,
        llvmInitializeNativeAsmParser=\iLLVMInitializeNativeAsmParser,
        llvmInitializeNativeDisassembler=\iLLVMInitializeNativeDisassembler,
        llvmInitializeNativeTarget=\iLLVMInitializeNativeTarget,

        LLVMModuleRef,
        llvmModuleCreateWithName=\iLLVMModuleCreateWithName,
        llvmPrintModuleToString=\iLLVMPrintModuleToString,
        llvmDisposeModule=\iLLVMDisposeModule,

        LLVMTypeRef,
        llvmInt32Type=\iLLVMInt32Type,
        llvmInt64Type=\iLLVMInt64Type,
        llvmIntType=\iLLVMIntType,
        llvmPointerType=\iLLVMPointerType,
        llvmFunctionType=\iLLVMFunctionType,
        llvmStructType=\iLLVMStructType,
        llvmVoidType=\iLLVMVoidType,
        llvmLabelType=\iLLVMLabelType
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
}

class LLVMModule satisfies Destroyable {
    LLVMModuleRef ref;

    shared new withName(String name) {
        llvmLibrary.initialize();

        ref = llvmModuleCreateWithName(name);
    }

    shared actual void destroy(Throwable? error) {
        llvmDisposeModule(ref);
    }

    string => llvm.printModuleToString(ref);
}

\IllvmLibrary llvm {
    llvmLibrary.initialize();
    return llvmLibrary;
}

