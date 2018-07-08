package org.americanteeth.ceylon_llvm;

import org.bytedeco.javacpp.*;
import static org.bytedeco.javacpp.LLVM.*;

class LLVM {
  public static LLVMValueRef constArray(LLVMTypeRef type, LLVMValueRef[] values) {
    return LLVMConstArray(type, new PointerPointer(values), values.length);
  }
}
