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
        llvmGetTypeKind=\iLLVMGetTypeKind,
        llvmGetElementType=\iLLVMGetElementType,

        /* LLVMTypeKind */
        llvmPointerTypeKind=\iLLVMPointerTypeKind,

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
        llvmGetNamedGlobal=\iLLVMGetNamedGlobal,

        LLVMBasicBlockRef,
        llvmAppendBasicBlock=\iLLVMAppendBasicBlock,
        llvmBasicBlockAsValue=\iLLVMBasicBlockAsValue,
        llvmGetBasicBlockTerminator=\iLLVMGetBasicBlockTerminator,
        llvmGetFirstInstruction=\iLLVMGetFirstInstruction,

        LLVMBuilderRef,
        llvmCreateBuilder=\iLLVMCreateBuilder,
        llvmPositionBuilder=\iLLVMPositionBuilder,
        llvmBuildPhi=\iLLVMBuildPhi,
        llvmBuildRetVoid=\iLLVMBuildRetVoid,
        llvmBuildRet=\iLLVMBuildRet,
        llvmBuildBr=\iLLVMBuildBr,
        llvmBuildCondBr=\iLLVMBuildCondBr,
        llvmBuildUnreachable=\iLLVMBuildUnreachable,
        llvmBuildLoad=\iLLVMBuildLoad,
        llvmBuildStore=\iLLVMBuildStore,

        /* LLVMLinkage, */
        llvmPrivateLinkage=\iLLVMPrivateLinkage,
        llvmExternalLinkage=\iLLVMExternalLinkage,

        llvmWriteBitcodeToFile=\iLLVMWriteBitcodeToFile
    }
}
import ceylon.interop.java { createJavaObjectArray }
import java.lang { ObjectArray }

"Enum class to package LLVMTypeKind values"
class LLVMTypeKind {
    shared Integer val;

    shared new pointerTypeKind {
        val = llvmPointerTypeKind;
    }

    hash => val.hash;
    equals(Object other)
        => if (is LLVMTypeKind other)
           then other.val == val
           else false;
}

"Convert integers to LLVMTypeKind"
LLVMTypeKind toTypeKind(Integer val) {
    if (val == LLVMTypeKind.pointerTypeKind.val) {
        return LLVMTypeKind.pointerTypeKind;
    }

    "No valid type kind found"
    assert(false);
}

"Namespace object for LLVM library functions."
object llvm {
    llvmInitializeNativeAsmPrinter();
    llvmInitializeNativeAsmParser();
    llvmInitializeNativeDisassembler();
    llvmInitializeNativeTarget();

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
    shared LLVMTypeKind getTypeKind(LLVMTypeRef ty)
        => toTypeKind(llvmGetTypeKind(ty));
    shared LLVMTypeRef getElementType(LLVMTypeRef ty)
        => llvmGetElementType(ty);

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
    shared LLVMValueRef addAlias(LLVMModuleRef ref, LLVMTypeRef ty,
            LLVMValueRef aliasee, String name)
        => llvmAddAlias(ref, ty, aliasee, name);
    shared LLVMValueRef? getNamedGlobal(LLVMModuleRef ref, String name)
        => llvmGetNamedGlobal(ref, name);

    shared LLVMBasicBlockRef appendBasicBlock(LLVMValueRef fn, String name)
        => llvmAppendBasicBlock(fn, name);
    shared LLVMValueRef basicBlockAsValue(LLVMBasicBlockRef bb)
        => llvmBasicBlockAsValue(bb);
    shared LLVMValueRef? getBasicBlockTerminator(LLVMBasicBlockRef bb)
        => llvmGetBasicBlockTerminator(bb);
    shared LLVMValueRef? getFirstInstruction(LLVMBasicBlockRef bb)
        => llvmGetFirstInstruction(bb);

    shared LLVMBuilderRef createBuilder() => llvmCreateBuilder();
    shared void positionBuilder(LLVMBuilderRef builder,
            LLVMBasicBlockRef bb, LLVMValueRef? instr = null)
        => llvmPositionBuilder(builder, bb, instr);
    shared LLVMValueRef buildPhi(LLVMBuilderRef builder, LLVMTypeRef ty,
            String name)
        => llvmBuildPhi(builder, ty, name);
    shared void buildRet(LLVMBuilderRef builder, LLVMValueRef? ret) {
        if (exists ret) {
            llvmBuildRet(builder, ret);
        } else {
            llvmBuildRetVoid(builder);
        }
    }
    shared void buildBr(LLVMBuilderRef builder, LLVMBasicBlockRef target)
        => llvmBuildBr(builder, target);
    shared void buildCondBr(LLVMBuilderRef builder, LLVMValueRef cond,
            LLVMBasicBlockRef t, LLVMBasicBlockRef f)
        => llvmBuildCondBr(builder, cond, t, f);
    shared void buildUnreachable(LLVMBuilderRef builder)
        => llvmBuildUnreachable(builder);
    shared LLVMValueRef buildLoad(LLVMBuilderRef builder, LLVMValueRef ptr,
            String name)
        => llvmBuildLoad(builder, ptr, name);
    shared void buildStore(LLVMBuilderRef builder, LLVMValueRef val,
            LLVMValueRef ptr)
        => llvmBuildStore(builder, val, ptr);

    shared void addIncoming(LLVMValueRef phi,
            [LLVMValueRef*] values,
            [LLVMBasicBlockRef*] blocks) {
        "Must have the same number of values and blocks"
        assert(values.size == blocks.size);

        LLVM.addIncoming(phi, createJavaObjectArray(values),
                createJavaObjectArray(blocks));
    }

    shared void writeBitcodeToFile(LLVMModuleRef ref, String path)
        => llvmWriteBitcodeToFile(ref, path);
}

"Wrapper object for LLVM Module"
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

    shared LLVMGlobalValue<T> lookupGlobal<T>(T ty, String name)
            given T satisfies LLVMType
        => LLVMGlobalValue(ty, llvm.getNamedGlobal(ref, name)
                else llvm.addGlobal(ref, ty.ref, name)).validated;

    shared LLVMValue<T> addAlias<T>(LLVMValue<T> val, String name)
            given T satisfies LLVMType
        => LLVMValue(val.type, llvm.addAlias(ref, val.type.ref, val.ref, name));

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
