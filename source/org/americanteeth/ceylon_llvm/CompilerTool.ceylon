import ceylon.ast.core {
    Node
}

import ceylon.ast.redhat {
    anyCompilationUnitToCeylon,
    RedHatTransformer,
    SimpleTokenFactory
}

import ceylon.interop.java {
    CeylonIterable,
    javaString
}

import ceylon.file {
    parsePath,
    createFileIfNil,
    File,
    Reader,
    Nil
}

import com.redhat.ceylon.compiler.typechecker {
    TypeCheckerBuilder
}

import com.redhat.ceylon.model.typechecker.model {
    Module
}

import com.redhat.ceylon.common.tool {
    argument,
    optionArgument,
    description
}

import com.redhat.ceylon.common.tools {
    CeylonTool,
    OutputRepoUsingTool,
    SourceArgumentsResolver
}

import com.redhat.ceylon.common.config {
    DefaultToolOptions
}

import com.redhat.ceylon.cmr.api {
    ArtifactContext
}

import ceylon.formatter {
    format
}
import ceylon.formatter.options {
    FormattingOptions
}

import java.util {
    List,
    JArrayList=ArrayList
}

import java.lang {
    JString=String
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

"Recover the source from the AST"
void printNodeAsCode(Node node)
    => format(node.transform(
        RedHatTransformer(SimpleTokenFactory())),
        FormattingOptions { maxLineLength = 80; });

"Compiler utility for baremetal compilation"
shared class CompilerTool() extends OutputRepoUsingTool(null) {
    variable List<JString> moduleOrFile_ = JArrayList<JString>();
    shared List<JString> moduleOrFile => moduleOrFile_;

    argument { argumentName = "moduleOrFile"; multiplicity = "*"; }
    assign moduleOrFile { moduleOrFile_ = moduleOrFile; }

    variable String triple_ = "";
    shared JString triple => javaString(triple_);

    optionArgument { longName = "triple"; argumentName = "target-triple"; }
    description ("Specify output target triple")
    assign triple { triple_ = triple.string; }

    shared actual void initialize(CeylonTool mt) {}

    shared actual void run() {
        value roots = DefaultToolOptions.compilerSourceDirs;
        value resources = DefaultToolOptions.compilerResourceDirs;
        value resolver = SourceArgumentsResolver(roots, resources, ".ceylon");

        if (triple_ == "") {
            value confProc = createProcess {
                command = "/usr/bin/llvm-config";
                arguments = ["--host-target"];
                error = currentError;
            };

            confProc.waitForExit();

            assert (is Reader r = confProc.output);
            assert (exists result = r.readLine()?.trim(Character.whitespace));
            triple_ = result;
        }

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
            value file = "/tmp/tmp`` tmpIdx++ ``.ll";

            unit.visit(preprocessVisitor);
            value bld = LLVMBuilder(triple_, mod.languageModule.rootPackage);
            unit.visit(bld);
            value result = bld.string;

            if (exists argList = argsMap[mod]) {
                argList.add(file);
            } else {
                argsMap.put(mod, ArrayList {
                        "-target", triple_, "-shared", "-fPIC", "-g",
                        "-lceylon",
                        "-o/tmp/``mod.nameAsString``-``mod.version``.cso",
                        file
                    });
            }

            assert (is File|Nil f = parsePath(file).resource);

            try (w = createFileIfNil(f).Overwriter()) {
                w.write(result.string);
            }
        }

        if (tmpIdx == 0) { return; }

        for (mod->cmd in argsMap) {
            value metaPath = "/tmp/tmp`` tmpIdx++ ``.ll";

            assert (is File|Nil metaFile = parsePath(metaPath).resource);
            try (w = createFileIfNil(metaFile).Overwriter()) {
                assert(exists bytes = serializeModule(mod));
                value data = ", ".join(bytes.map((x) => "i8 ``x``"));
                w.write("target triple = \"``triple_``\"

                         @model = constant [``bytes.size`` x i8] [``data``], \
                         section \"ceylon.module\", align 1");
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
