import com.redhat.ceylon.common {
    Backends
}

import com.redhat.ceylon.model.typechecker.model {
    Module
}

import org.americanteeth.ceylon_llvm {
    baremetalBackend
}

"Write the annotations for a module to the blob."
shared void storeModuleAnnotations(CSOBlob buf, Module m) {
    variable value packed1 = 0.byte;

    /* TODO: Native? */

    buf.put(packed1);
    buf.put(0.byte);

    for (ann in m.annotations) {
        buf.putAnnotation(ann);
    }

    buf.put(0.byte);
}

"Read annotations for a module from a blob."
shared void loadModuleAnnotations(CSOBlob data, Module target) {
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
