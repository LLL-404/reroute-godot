#if TOOLS
using Godot;
using Godot.Collections;

namespace GodotMCP.Handlers;

public abstract class BaseHandler
{
    protected EditorPlugin Plugin { get; }

    protected BaseHandler(EditorPlugin plugin)
    {
        Plugin = plugin;
    }

    public abstract Dictionary Handle(string command, Dictionary parms);

    protected Node GetEditedRoot() =>
        EditorInterface.Singleton.GetEditedSceneRoot();

    protected Node FindNode(string path)
    {
        var root = GetEditedRoot();
        if (root == null) return null;
        if (path == "." || path == root.Name) return root;
        if (path.StartsWith("/root/"))
            path = path["/root/".Length..];
        var rootName = root.Name + "/";
        if (path.StartsWith(rootName))
            path = path[rootName.Length..];
        else if (path == root.Name)
            return root;
        return root.GetNodeOrNull(path);
    }

    protected EditorUndoRedoManager GetUndoRedo() =>
        Plugin.GetUndoRedo();

    protected Dictionary Success(Dictionary data = null) =>
        new() { { "success", true }, { "data", data ?? new Dictionary() } };

    protected Dictionary Error(string message) =>
        new() { { "success", false }, { "error", message } };

    protected static Variant GetOr(Dictionary dict, string key, Variant defaultValue) =>
        dict.ContainsKey(key) ? dict[key] : defaultValue;

    /// 拼接目录与子项为资源路径。
    /// 不能用 path.TrimEnd('/')：它会吃掉 res:// 的第二个斜杠（res:// → res:），
    /// 导致根路径下列出的路径不可回灌（read_file 报 File not found）、递归进不去子目录。
    /// 这里只把目录补齐到「恰好一个尾斜杠」。
    protected static string JoinPath(string dir, string name) =>
        (dir.EndsWith("/") ? dir : dir + "/") + name;
}
#endif
