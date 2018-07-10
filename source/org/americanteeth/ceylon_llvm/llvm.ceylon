import org.bytedeco.javacpp {
    X=LLVM {
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
        llvmAddFunction=\iLLVMAddFunction,
        llvmGetNamedFunction=\iLLVMGetNamedFunction,

        LLVMTypeRef,
        llvmInt8Type=\iLLVMInt8Type,
        llvmInt32Type=\iLLVMInt32Type,
        llvmInt64Type=\iLLVMInt64Type,
        llvmIntType=\iLLVMIntType,
        llvmPointerType=\iLLVMPointerType,
        llvmVoidType=\iLLVMVoidType,
        llvmLabelType=\iLLVMLabelType,
        llvmArrayType=\iLLVMArrayType,
        llvmPrintTypeToString=\iLLVMPrintTypeToString,

        LLVMValueRef,
        llvmConstInt=\iLLVMConstInt,
        llvmConstNull=\iLLVMConstNull,
        llvmGetUndef=\iLLVMGetUndef,
        llvmAddGlobal=\iLLVMAddGlobal,
        llvmIsGlobalConstant=\iLLVMIsGlobalConstant,
        llvmSetGlobalConstant=\iLLVMSetGlobalConstant,
        llvmGetInitializer=\iLLVMGetInitializer,
        llvmSetInitializer=\iLLVMSetInitializer,
        llvmGetSection=\iLLVMGetSection,
        llvmSetSection=\iLLVMSetSection,
        llvmGetAlignment=\iLLVMGetAlignment,
        llvmSetAlignment=\iLLVMSetAlignment,
        llvmGetParam=\iLLVMGetParam,
        llvmTypeOf=\iLLVMTypeOf,
        llvmSetLinkage=\iLLVMSetLinkage,
        llvmGetLinkage=\iLLVMGetLinkage,
        llvmPrintValueToString=\iLLVMPrintValueToString,
        llvmAddAlias=\iLLVMAddAlias,

        LLVMBasicBlockRef,
        llvmAppendBasicBlock=\iLLVMAppendBasicBlock,

        /* LLVMLinkage, */
        llvmPrivateLinkage=\iLLVMPrivateLinkage,
        llvmExternalLinkage=\iLLVMExternalLinkage,

        llvmWriteBitcodeToFile=\iLLVMWriteBitcodeToFile
    }
}
import ceylon.interop.java { createJavaObjectArray }
import java.lang { ObjectArray }

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

    shared Integer privateLinkage = llvmPrivateLinkage;
    shared Integer externalLinkage = llvmExternalLinkage;

    shared LLVMTypeRef int64Type()
        => llvmInt64Type();
    shared LLVMTypeRef pointerType(LLVMTypeRef t)
        => llvmPointerType(t, 0); // The 0 should be ADDRESS_SPACE_GENERIC
    shared LLVMTypeRef functionType(LLVMTypeRef? ret, [LLVMTypeRef*] args)
        => LLVM.functionType(ret else llvmVoidType(),
                createJavaObjectArray(args), false);
    shared LLVMTypeRef structType([LLVMTypeRef*] items)
        => LLVM.structType(createJavaObjectArray(items), false);

    shared LLVMTypeRef labelType => llvmLabelType();
    shared LLVMTypeRef i64Type => llvmInt64Type();
    shared LLVMTypeRef i32Type => llvmInt32Type();
    shared LLVMTypeRef i8Type => llvmInt8Type();
    shared LLVMTypeRef intType(Integer bits) => llvmIntType(bits);
    shared LLVMTypeRef arrayType(LLVMTypeRef element, Integer size)
        => llvmArrayType(element, size);
    shared String printTypeToString(LLVMTypeRef ref)
        => llvmPrintTypeToString(ref).getString();

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

    shared LLVMValueRef addFunction(LLVMModuleRef ref, String name,
            LLVMTypeRef type)
        => llvmAddFunction(ref, name, type);
    shared LLVMValueRef? getNamedFunction(LLVMModuleRef ref, String name)
        => llvmGetNamedFunction(ref, name);

    shared LLVMValueRef constInt(LLVMTypeRef t, Integer val)
        => llvmConstInt(t, val, 1 /* sign extend: true */);
    shared LLVMValueRef constNull(LLVMTypeRef t) => llvmConstNull(t);
    shared LLVMValueRef undef(LLVMTypeRef t) => llvmGetUndef(t);
    shared LLVMValueRef addGlobal(LLVMModuleRef ref, LLVMTypeRef t, String name)
        => llvmAddGlobal(ref, t, name);
    shared Boolean isGlobalConstant(LLVMValueRef ref)
        => llvmIsGlobalConstant(ref) != 0;
    shared void setGlobalConstant(LLVMValueRef ref, Boolean isit)
        => llvmSetGlobalConstant(ref, isit then 1 else 0);
    shared LLVMValueRef getInitializer(LLVMValueRef ref)
        => llvmGetInitializer(ref);
    shared void setInitializer(LLVMValueRef ref, LLVMValueRef other)
        => llvmSetInitializer(ref, other);
    shared String getSection(LLVMValueRef ref)
        => llvmGetSection(ref).getString();
    shared void setSection(LLVMValueRef ref, String section)
        => llvmSetSection(ref, section);
    shared Integer getAlignment(LLVMValueRef ref)
        => llvmGetAlignment(ref);
    shared void setAlignment(LLVMValueRef ref, Integer alignment)
        => llvmSetAlignment(ref, alignment);
    shared LLVMValueRef constArray(LLVMTypeRef ty, [LLVMValueRef*] elements)
        => LLVM.constArray(ty, createJavaObjectArray(elements));
    shared LLVMValueRef getParam(LLVMValueRef ref, Integer idx)
        => llvmGetParam(ref, idx);
    shared LLVMTypeRef typeOf(LLVMValueRef ref)
        => llvmTypeOf(ref);
    shared void setLinkage(LLVMValueRef ref, Integer linkage)
        => llvmSetLinkage(ref, linkage);
    shared Integer getLinkage(LLVMValueRef ref)
        => llvmGetLinkage(ref);
    shared String printValueToString(LLVMValueRef ref)
        => llvmPrintValueToString(ref).getString();
    shared LLVMValueRef llvmAddAlias(LLVMModuleRef ref, LLVMTypeRef ty,
            LLVMValueRef aliasee, String name)
        => llvmAddAlias(ref, ty, aliasee, name);

    shared LLVMBasicBlockRef appendBasicBlock(LLVMValueRef fn, String name)
        => llvmAppendBasicBlock(fn, name);

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

    shared LLVMGlobalValue<T> addGlobal<T>(T ty, String name)
            given T satisfies LLVMType
        => LLVMGlobalValue(ty, llvm.addGlobal(ref, ty.ref, name));

    shared LLVMGlobalValue<T> addAlias<T>(LLVMValue<T> val, String name)
            given T satisfies LLVMType
        => LLVMGlobalValue(val.type,
                llvmAddAlias(ref, val.type.ref, val.ref, name));

    shared LLVMValueRef refForFunction(String name, AnyLLVMFunctionType t) {
        if (exists old = llvm.getNamedFunction(ref, name)) {
            "Function should have the expected type"
            assert(t.ref == llvm.typeOf(old));
            return old;
        }

        return llvm.addFunction(ref, name, t.ref);
    }

    string => llvm.printModuleToString(ref);
}

\IllvmLibrary llvm {
    llvmLibrary.initialize();
    return llvmLibrary;
}
