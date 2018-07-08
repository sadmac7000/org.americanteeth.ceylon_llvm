native ("jvm") module org.americanteeth.ceylon_llvm "1.3.4-SNAPSHOT" {
    shared import org.eclipse.ceylon.typechecker "1.3.4-SNAPSHOT";
    import ceylon.buffer "1.3.4-SNAPSHOT";
    shared import ceylon.file "1.3.4-SNAPSHOT";
    import ceylon.process "1.3.4-SNAPSHOT";
    import ceylon.ast.core "1.3.4-SNAPSHOT";
    import ceylon.ast.create "1.3.4-SNAPSHOT";
    import ceylon.ast.redhat "1.3.4-SNAPSHOT";
    import ceylon.interop.java "1.3.4-SNAPSHOT";
    import ceylon.collection "1.3.4-SNAPSHOT";
    import maven:"org.bytedeco.javacpp-presets":"llvm" "5.0.1-1.4.1";
    import maven:"org.bytedeco.javacpp-presets":"llvm-platform" "5.0.1-1.4.1";
    import maven:"org.bytedeco":"javacpp" "1.4.1";
    import org.eclipse.ceylon.model "1.3.4-SNAPSHOT";
    shared import org.eclipse.ceylon.common "1.3.4-SNAPSHOT";
    shared import org.eclipse.ceylon.cli "1.3.4-SNAPSHOT";
    shared import "org.eclipse.ceylon.module-resolver" "1.3.4-SNAPSHOT";
    shared import java.base "8";
}
