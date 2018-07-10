import ceylon.ast.core {
    Node
}

import ceylon.ast.redhat {
    anyCompilationUnitToCeylon,
    RedHatTransformer,
    SimpleTokenFactory
}

import ceylon.interop.java {
    CeylonIterable
}

import ceylon.file {
    parsePath,
    createFileIfNil,
    File,
    Reader,
    Nil
}

import org.eclipse.ceylon.compiler.typechecker {
    TypeCheckerBuilder
}

import org.eclipse.ceylon.model.typechecker.model {
    Module
}

import org.eclipse.ceylon.common {
    Backends
}

import org.eclipse.ceylon.common.tool {
    argument,
    option,
    optionArgument,
    description
}

import org.eclipse.ceylon.common.tools {
    CeylonTool,
    OutputRepoUsingTool,
    SourceArgumentsResolver
}

import org.eclipse.ceylon.common.config {
    DefaultToolOptions
}

import org.eclipse.ceylon.cmr.api {
    ArtifactContext
}

import java.util {
    List,
    JArrayList=ArrayList
}

import java.lang {
    JString=String,
    Types {
            javaString=nativeString
    }
}

import ceylon.process {
    createProcess,
    currentOutput,
    currentError
}

import ceylon.collection {
    ArrayList,
    HashMap
}

import java.io {
    JFile=File
}

import org.americanteeth.ceylon_llvm.cso {
    moduleManagerFactory,
    serializeModule
}

/*
import ceylon.formatter {
    format
}
import ceylon.formatter.options {
    FormattingOptions
}

"Recover the source from the AST"
void printNodeAsCode(Node node)
    => format(node.transform(
        RedHatTransformer(SimpleTokenFactory())),
        FormattingOptions { maxLineLength = 80; });
*/

"Compiler utility for baremetal compilation"
shared class CompilerTool() extends OutputRepoUsingTool(null) {
    variable List<JString> moduleOrFile_ = JArrayList<JString>();
    shared List<JString> moduleOrFile => moduleOrFile_;

    argument { argumentName = "moduleOrFile"; multiplicity = "*"; }
    assign moduleOrFile { moduleOrFile_ = moduleOrFile; }

    variable Boolean showIR_ = false;
    shared Boolean showIR => showIR_;

    option { longName = "show-ir"; }
    assign showIR { showIR_ = showIR; }

    variable String? triple_ = null;
    shared JString? triple => if (exists t = triple_)
        then javaString(t) else null;

    optionArgument { longName = "triple"; argumentName = "target-triple"; }
    description ("Specify output target triple")
    assign triple { triple_ = triple?.string; }

    shared actual void initialize(CeylonTool mt) {}

    shared actual void run() {
        value roots = DefaultToolOptions.compilerSourceDirs;
        value resources = DefaultToolOptions.compilerResourceDirs;
        value resolver = SourceArgumentsResolver(roots, resources, ".ceylon");

        resolver.cwd(cwd).expandAndParse(moduleOrFile, baremetalBackend);
        value builder = TypeCheckerBuilder();

        for (root in CeylonIterable(roots)) {
            builder.addSrcDirectory(root);
        }

        builder.setSourceFiles(resolver.sourceFiles);
        builder.setRepositoryManager(repositoryManager);
        builder.moduleManagerFactory(moduleManagerFactory);

        if (!resolver.sourceModules.empty) {
            builder.setModuleFilters(resolver.sourceModules);
        }

        value typeChecker = builder.typeChecker;
        typeChecker.process(true);

        value phasedUnits = CeylonIterable(
            typeChecker.phasedUnits.phasedUnits);

        variable value tmpIdx = 0;

        value argsMap = HashMap<Module,ArrayList<String>>();

        for (phasedUnit in phasedUnits) {
            value unit = anyCompilationUnitToCeylon(
                phasedUnit.compilationUnit,
                augmentNode);
            value mod = phasedUnit.\ipackage.\imodule;
            value file = "/tmp/tmp`` tmpIdx++ ``.bc";

            if (mod.nativeBackends != Backends.\iANY,
                ! mod.nativeBackends.supports(baremetalBackend)) {
                print("Error: Module does not support this back end:
                        ``mod.name``");
                return;
            }

            unit.visit(preprocessVisitor);

            try (bld = LLVMBuilder(phasedUnit.unit.fullPath, triple_,
                        mod.languageModule.rootPackage)) {
                unit.visit(bld);

                if (showIR) {
                    print(bld);
                }

                bld.writeBitcodeFile(file);
            }

            if (exists argList = argsMap[mod]) {
                argList.add(file);
            } else {
                argsMap.put(mod, ArrayList {
                        "-shared", "-fPIC", "-g", "-lceylon",
                        "-o/tmp/``mod.nameAsString``-``mod.version``.cso",
                        file
                    });
            }
        }

        if (tmpIdx == 0) { return; }

        for (mod->cmd in argsMap) {
            value metaPath = "/tmp/tmp`` tmpIdx++ ``.bc";

            try (m = LLVMModule.withName("@meta")) {
                assert(exists bytes = serializeModule(mod));
                value byteValues = bytes.collect((x) => I8Lit(x));

                if (exists t = triple_) {
                    m.target = t;
                }

                value model = m.addGlobal(ArrayType(i8, byteValues.size), "model");
                model.constant = true;
                model.section = "ceylon.module";
                model.alignment = 1;
                model.initializer = constArray(i8, byteValues);

                m.writeBitcodeFile(metaPath);
            }

            cmd.add(metaPath);
        }

        for (mod->args in argsMap) {
            createProcess {
                command = "/usr/bin/clang";
                arguments = args;
                output = currentOutput;
                error = currentError;
            }.waitForExit();

            value artifactContext = ArtifactContext(null, mod.nameAsString,
                    mod.version, ".cso");

            outputRepositoryManager.removeArtifact(artifactContext);
            outputRepositoryManager.putArtifact(
                    artifactContext,
                JFile("/tmp/``mod.nameAsString``-``mod.version``.cso"));
        }
    }
}
