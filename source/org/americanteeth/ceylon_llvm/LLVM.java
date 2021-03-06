package org.americanteeth.ceylon_llvm;

import org.bytedeco.javacpp.*;
import static org.bytedeco.javacpp.LLVM.*;

class LLVM {
  public static LLVMValueRef constArray(LLVMTypeRef type,
      LLVMValueRef[] values) {
    return LLVMConstArray(type, new PointerPointer(values), values.length);
  }

  public static LLVMTypeRef functionType(LLVMTypeRef ret, LLVMTypeRef[] args,
      boolean variadic) {
    int variadic_i = 0;

    if (variadic) {
      variadic_i = 1;
    }

    return LLVMFunctionType(ret, new PointerPointer(args), args.length,
        variadic_i);
  }

  public static LLVMTypeRef structType(LLVMTypeRef[] items, boolean pack) {
    int pack_i = 0;

    if (pack) {
      pack_i = 1;
    }

    return LLVMStructType(new PointerPointer(items), items.length, pack_i);
  }

  public static void addIncoming(LLVMValueRef phi, LLVMValueRef[] values,
      LLVMBasicBlockRef[] blocks) {
    LLVMAddIncoming(phi, new PointerPointer(values),
        new PointerPointer(blocks), blocks.length);
  }

  public static LLVMValueRef buildGEP(LLVMBuilderRef builder, LLVMValueRef ptr,
      LLVMValueRef[] indices, String name) {
    return LLVMBuildGEP(builder, ptr, new PointerPointer(indices),
        indices.length, name);
  }

  public static LLVMValueRef buildCall(LLVMBuilderRef builder, LLVMValueRef fn,
      LLVMValueRef[] args, String name) {
    return LLVMBuildCall(builder, fn, new PointerPointer(args), args.length,
        name);
  }

  public static LLVMValueRef constStruct(LLVMValueRef[] values,
      boolean pack) {
    int pack_i = 0;

    if (pack) {
      pack_i = 1;
    }

    return LLVMConstStruct(new PointerPointer(values), values.length, pack_i);
  }
}
