import com.redhat.ceylon.common {
    Backends
}

import com.redhat.ceylon.model.typechecker.model {
    Class,
    Constructor,
    Declaration,
    Module,
    Value
}

"First byte of packed annotation flags."
object packedAnnotations1 {
    "Flag for the shared annotation."
    shared Byte \ishared = 1.byte;

    "Flag for the actual annotation."
    shared Byte \iactual = 2.byte;

    "Flag for the formal annotation."
    shared Byte \iformal = 4.byte;

    "Flag for the default annotation."
    shared Byte \idefault = 8.byte;

    "Flag for the native annotation."
    shared Byte \inative = 16.byte;

    "Flag for the annotation annotation."
    shared Byte \iannotation = 32.byte;

    "Flag for the sealed annotation."
    shared Byte \isealed = 64.byte;

    "Flag for the final annotation."
    shared Byte \ifinal = 128.byte;
}

"Second byte of packed annotation flags."
object packedAnnotations2 {
    "Flag for the abstract annotation."
    shared Byte \iabstract = 1.byte;

    "Flag for the late annotation."
    shared Byte \ilate = 2.byte;

    "Flag for the variable annotation."
    shared Byte \ivariable = 4.byte;
}

"Write the annotations for a declaration to the blob."
void storeAnnotations(CSOBlob buf, Declaration d) {
    variable value packed1 = 0.byte;
    variable value packed2 = 0.byte;

    if (d.\ishared) {
        packed1 = packed1.or(packedAnnotations1.\ishared);
    }

    if (d.\iactual) {
        packed1 = packed1.or(packedAnnotations1.\iactual);
    }

    if (d.\iformal) {
        packed1 = packed1.or(packedAnnotations1.\iformal);
    }

    if (d.\idefault) {
        packed1 = packed1.or(packedAnnotations1.\idefault);
    }

    /* TODO: Native? */

    if (d.\iannotation) {
        packed1 = packed1.or(packedAnnotations1.\iannotation);
    }

    if (is Class d, d.\ifinal) {
        packed1 = packed1.or(packedAnnotations1.\ifinal);
    }

    if (is Class|Constructor d, d.\iabstract) {
        packed2 = packed2.or(packedAnnotations2.\iabstract);
    }

    if (is Value d, d.\ilate) {
        packed2 = packed2.or(packedAnnotations2.\ilate);
    }

    if (is Value d, d.\ivariable) {
        packed2 = packed2.or(packedAnnotations2.\ivariable);
    }

    buf.put(packed1);
    buf.put(packed2);

    for (ann in d.annotations) {
        buf.putAnnotation(ann);
    }

    buf.put(0.byte);
}

"Read the annotations for a declaration from a blob."
void loadAnnotations(CSOBlob data, Declaration target) {
    variable value packed1 = data.get();
    variable value packed2 = data.get();

    target.\ishared = packed1.and(packedAnnotations1.\ishared) != 0.byte;

    target.\iactual = packed1.and(packedAnnotations1.\iactual) != 0.byte;

    target.\iformal = packed1.and(packedAnnotations1.\iformal) != 0.byte;

    target.\idefault = packed1.and(packedAnnotations1.\idefault) != 0.byte;

    if (packed1.and(packedAnnotations1.\inative) != 0.byte) {
        target.nativeBackends = backend.asSet();
    } else {
        target.nativeBackends = Backends.\iANY;
    }

    target.\iannotation = packed1.and(packedAnnotations1.\iannotation)
        != 0.byte;

    if (is Class t = target) {
        t.\ifinal = packed1.and(packedAnnotations1.\ifinal) != 0.byte;
    }

    if (is Class t = target) {
        t.\iabstract = packed2.and(packedAnnotations2.\iabstract) != 0.byte;
    }

    if (is Constructor t = target) {
        t.\iabstract = packed2.and(packedAnnotations2.\iabstract) != 0.byte;
    }

    if (is Value t = target) {
        t.\ilate = packed2.and(packedAnnotations2.\ilate) != 0.byte;

        t.\ivariable = packed2.and(packedAnnotations2.\ivariable) != 0.byte;
    }

    while (exists ann = data.getAnnotation()) {
        target.annotations.add(ann);
    }
}

"Write the annotations for a module to the blob."
void storeModuleAnnotations(CSOBlob buf, Module m) {
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
void loadModuleAnnotations(CSOBlob data, Module target) {
    variable value packed1 = data.get();
    data.get(); // Throw away always-empty byte.

    if (packed1.and(packedAnnotations1.\inative) != 0.byte) {
        target.nativeBackends = backend.asSet();
    } else {
        target.nativeBackends = Backends.\iANY;
    }

    while (exists ann = data.getAnnotation()) {
        target.annotations.add(ann);
    }
}
