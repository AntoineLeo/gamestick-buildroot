import re, sys

header = sys.argv[1]
with open(header) as f:
    content = f.read()

print("#include <GLES2/gl2.h>")
print()

pattern = r'GL_APICALL\s+([\w\s\*]+?)\s*GL_APIENTRY\s+(\w+)\s*\(([^;]*)\)\s*;'
for m in re.finditer(pattern, content):
    ret = m.group(1).strip()
    name = m.group(2)
    params = m.group(3).strip() or "void"
    if ret == "void":
        body = "{}"
    elif '*' in ret:
        body = "{ return (void*)0; }"
    else:
        body = "{ return (" + ret + ")0; }"
    print(f"GL_APICALL {ret} GL_APIENTRY {name}({params}) " + body)
