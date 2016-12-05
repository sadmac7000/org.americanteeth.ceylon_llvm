import ceylon.buffer.charset {
    utf8
}

"Get a hex string for a byte"
String byteHex(Byte b)
        => Integer.format(b.unsigned, 16).padLeading(2, '0').uppercased;

"Turn Ceylon escape sequences in to LLVM escape sequences"
[String, Integer] processEscapes(String input) {
    String unescaped = removeEscapes(input);
    variable Integer len = 0;

    {String*} fixChar(Character c) {
        value utf = utf8.encode(c.string);
        len += utf.size;

        if (utf.size == 1, !c.control && (!c.whitespace || c==' '),
            c != '\\') {
            return { c.string };
        }

        return utf.map((x) => "\\``byteHex(x)``");
    }

    return [unescaped.flatMap(fixChar).fold("")((x, y) => x + y), len];
}

"Turn Ceylon escape sequences in to characters"
String removeEscapes(String input) {
    value segments = input.split('\\'.equals, false);
    value leader = segments.first;

    String doProcess([String+] items) {
        value slashes = items[0];
        assert (exists body = items[1]);
        assert (items.size == 2);
        value leadingSlashes = slashes[0 : slashes.size/2];

        if (slashes.size%2 == 0) { return leadingSlashes + body; }
        if (exists b = body[0], b == '{') {
            assert (exists close = body.firstOccurrence('}'));
            return leadingSlashes + "<Unsupported>" + body[close+1 ...];
        }

        value newChar = switch (body[0])
            case ('b') '\b'
            case ('t') '\t'
            case ('n') '\n'
            case ('f') '\f'
            case ('r') '\r'
            case ('e') '\e'
            case ('0') '\0'
            else body[0];
        return leadingSlashes + (newChar?.string else "") + body[1...];
    }

    return segments.rest.partition(2).map(doProcess).fold(leader)((x, y) => x +
                    y);
}
