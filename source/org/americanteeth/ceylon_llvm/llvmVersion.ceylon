import ceylon.process {
    createProcess,
    currentError
}

import ceylon.file {
    Reader
}

"Get the current LLVM version"
[Integer, Integer] getLLVMVersion() {
    value proc = createProcess {
        command = "/usr/bin/llvm-config";
        arguments = ["--version"];
        error = currentError;
    };

    proc.waitForExit();

    assert (is Reader r = proc.output);
    assert (exists result = r.readLine());

    value nums = result.split((x) => x == '.')
        .map((x) => x.trimmed)
        .take(2)
        .map(parseInteger).sequence();

    assert (exists major = nums[0],
        exists minor = nums[1]);

    "LLVM version should be = 3.x"
    assert (major == 3);

    return [major, minor];
}

"The current LLVM version"
[Integer, Integer] llvmVersion = getLLVMVersion();
