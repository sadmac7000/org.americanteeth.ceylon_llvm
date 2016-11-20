import com.redhat.ceylon.model.typechecker.model {
    Annotation,
    Declaration,
    Module,
    Class,
    Constructor,
    Value
}

import com.redhat.ceylon.common {
    Backends
}

import org.americanteeth.ceylon_llvm {
    baremetalBackend
}

class AnnotationData(\ishared, \iactual, \iformal, \idefault, \inative,
        \ifinal, \iabstract, \iannotation, \ilate, \ivariable, annotations) {

    shared Boolean \ishared;
    shared Boolean \iactual;
    shared Boolean \iformal;
    shared Boolean \idefault;
    shared Boolean \inative;
    shared Boolean \ifinal;
    shared Boolean \iabstract;
    shared Boolean \iannotation;
    shared Boolean \ilate;
    shared Boolean \ivariable;
    shared [Annotation*] annotations;

    shared void apply(Declaration|Module m) {
        if (is Declaration m) {
            m.\ishared = \ishared;
            m.\iactual = \iactual;
            m.\iformal = \iformal;
            m.\idefault = \idefault;
            m.\iannotation = \iannotation;

            if (\inative) {
                m.nativeBackends = baremetalBackend.asSet();
            } else {
                m.nativeBackends = Backends.\iANY;
            }
        }

        if (is Module m) {
            if (\inative) {
                m.nativeBackends = baremetalBackend.asSet();
            } else {
                m.nativeBackends = Backends.\iANY;
            }
        }

        if (is Class m) {
            m.\ifinal = \ifinal;
            m.\iabstract = \iabstract;
        }

        if (is Constructor m) {
            m.\iabstract = \iabstract;
        }

        if (is Value m) {
            m.\ilate = \ilate;
            m.\ivariable = \ivariable;
        }

        for (ann in annotations) {
            m.annotations.add(ann);
        }
    }
}
