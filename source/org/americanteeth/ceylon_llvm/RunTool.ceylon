import com.redhat.ceylon.common.tools {
    RepoUsingTool
}

import com.redhat.ceylon.common {
    ModuleUtil
}

import com.redhat.ceylon.cmr.api {
    ModuleQuery
}

import com.redhat.ceylon.common.tool {
    argument=argument__SETTER
}

shared class RunTool() extends RepoUsingTool(null) {
    shared variable argument {
        argumentName = "module";
        multiplicity = "1";
        order = 1;
    }
    String moduleString = "";

    shared actual void run() {
        String moduleName = ModuleUtil.moduleName(moduleString);
        String? moduleVersion =
            checkModuleVersionsOrShowSuggestions(repositoryManager, moduleName,
                ModuleUtil.moduleVersion(moduleString),
                ModuleQuery.Type.\iALL, null, null, null, null, null);
        print(moduleName);
        print(moduleVersion);
    }
}
