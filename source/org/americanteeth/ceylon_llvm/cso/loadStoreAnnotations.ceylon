import org.eclipse.ceylon.common {
    Backends
}

import org.eclipse.ceylon.model.typechecker.model {
    Module
}

import org.americanteeth.ceylon_llvm {
    baremetalBackend
}

"Write the annotations for a module to the blob."
void storeModuleAnnotations(Blob buf, Module m) {
    if (m.nativeBackends != Backends.\iANY) {
        buf.put(packedAnnotations1.\inative);
    } else {
        buf.put(0.byte);
    }

    buf.put(0.byte); // Second packed annotation byte.

    for (ann in m.annotations) {
        buf.putAnnotation(ann);
    }

    buf.put(0.byte);
}

"Read annotations for a module from a blob."
void loadModuleAnnotations(Blob data, Module target) {
    variable value packed1 = data.get();
    data.get(); // Throw away always-empty byte.

    if (packed1.and(packedAnnotations1.\inative) != 0.byte) {
        target.nativeBackends = baremetalBackend.asSet();
    } else {
        target.nativeBackends = Backends.\iANY;
    }

    while (exists ann = data.getAnnotation()) {
        target.annotations.add(ann);
    }
}
