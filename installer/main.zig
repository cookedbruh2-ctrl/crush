//! Crush Windows x64 installer (standalone PE setup.exe).
//! Installs into %LocalAppData%\Crush, creates shortcuts, registers uninstall + deep links.
const std = @import("std");
const w = std.os.windows;
const WINAPI = w.WINAPI;
const BOOL = w.BOOL;
const DWORD = w.DWORD;
const HWND = w.HWND;
const HINSTANCE = w.HINSTANCE;
const HANDLE = w.HANDLE;
const FALSE = w.FALSE;

const PRODUCT_NAME = "Crush";
const PRODUCT_VERSION = "0.5.0";
const PRODUCT_PUBLISHER = "Mally";
const PRODUCT_URL = "https://github.com/cookedbruh2-ctrl/crush";
const INSTALL_DIR_NAME = "Crush";
const EXE_NAME = "crush.exe";
const UNINSTALLER_NAME = "Uninstall Crush.exe";

const icon_bytes = @embedFile("assets/icon.ico");
const open_game_bat = @embedFile("assets/open_game.bat");
const vcruntime140 = @embedFile("assets/vcruntime140.dll");
const vcruntime140_1 = @embedFile("assets/vcruntime140_1.dll");

const launcher_note =
    \\Crush Bootstrapper
    \\==================
    \\Version: 0.5.0
    \\
    \\Installed by the Crush standalone Windows installer.
    \\Repo: https://github.com/cookedbruh2-ctrl/crush
    \\
;

const MessageBoxW = w.user32.MessageBoxW;
const MB_OK: UINT = 0x00000000;
const MB_OKCANCEL: UINT = 0x00000001;
const MB_YESNO: UINT = 0x00000004;
const MB_ICONINFORMATION: UINT = 0x00000040;
const MB_ICONQUESTION: UINT = 0x00000020;
const MB_ICONERROR: UINT = 0x00000010;
const IDYES: i32 = 6;
const IDCANCEL: i32 = 2;
const UINT = u32;

const GENERIC_WRITE: DWORD = 0x40000000;
const CREATE_ALWAYS: DWORD = 2;
const FILE_ATTRIBUTE_NORMAL: DWORD = 0x80;
const INVALID_HANDLE_VALUE: HANDLE = @as(HANDLE, @ptrFromInt(std.math.maxInt(usize)));

const CSIDL_LOCAL_APPDATA: i32 = 0x001c;
const CSIDL_STARTMENU: i32 = 0x000b;
const CSIDL_DESKTOPDIRECTORY: i32 = 0x0010;
const SHGFP_TYPE_CURRENT: DWORD = 0;

const HKEY_CURRENT_USER: usize = 0x80000001;
const KEY_WRITE: DWORD = 0x20006;
const REG_OPTION_NON_VOLATILE: DWORD = 0;
const REG_SZ: DWORD = 1;
const REG_DWORD: DWORD = 4;
const ERROR_SUCCESS: DWORD = 0;
const MAX_PATH: usize = 260;

extern "kernel32" fn GetModuleFileNameW(hModule: ?HINSTANCE, lpFilename: [*]u16, nSize: DWORD) callconv(WINAPI) DWORD;
extern "kernel32" fn CreateFileW(
    lpFileName: [*:0]const u16,
    dwDesiredAccess: DWORD,
    dwShareMode: DWORD,
    lpSecurityAttributes: ?*anyopaque,
    dwCreationDisposition: DWORD,
    dwFlagsAndAttributes: DWORD,
    hTemplateFile: ?HANDLE,
) callconv(WINAPI) HANDLE;
extern "kernel32" fn WriteFile(
    hFile: HANDLE,
    lpBuffer: [*]const u8,
    nNumberOfBytesToWrite: DWORD,
    lpNumberOfBytesWritten: ?*DWORD,
    lpOverlapped: ?*anyopaque,
) callconv(WINAPI) BOOL;
extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(WINAPI) BOOL;
extern "kernel32" fn CreateDirectoryW(lpPathName: [*:0]const u16, lpSecurityAttributes: ?*anyopaque) callconv(WINAPI) BOOL;
extern "kernel32" fn GetEnvironmentVariableW(lpName: [*:0]const u16, lpBuffer: [*]u16, nSize: DWORD) callconv(WINAPI) DWORD;
extern "kernel32" fn CopyFileW(lpExistingFileName: [*:0]const u16, lpNewFileName: [*:0]const u16, bFailIfExists: BOOL) callconv(WINAPI) BOOL;
extern "kernel32" fn DeleteFileW(lpFileName: [*:0]const u16) callconv(WINAPI) BOOL;
extern "kernel32" fn RemoveDirectoryW(lpPathName: [*:0]const u16) callconv(WINAPI) BOOL;

extern "shell32" fn SHGetFolderPathW(
    hwnd: ?HWND,
    csidl: i32,
    hToken: ?HANDLE,
    dwFlags: DWORD,
    pszPath: [*]u16,
) callconv(WINAPI) i32;

extern "advapi32" fn RegCreateKeyExW(
    hKey: usize,
    lpSubKey: [*:0]const u16,
    Reserved: DWORD,
    lpClass: ?[*:0]const u16,
    dwOptions: DWORD,
    samDesired: DWORD,
    lpSecurityAttributes: ?*anyopaque,
    phkResult: *usize,
    lpdwDisposition: ?*DWORD,
) callconv(WINAPI) DWORD;
extern "advapi32" fn RegSetValueExW(
    hKey: usize,
    lpValueName: ?[*:0]const u16,
    Reserved: DWORD,
    dwType: DWORD,
    lpData: [*]const u8,
    cbData: DWORD,
) callconv(WINAPI) DWORD;
extern "advapi32" fn RegCloseKey(hKey: usize) callconv(WINAPI) DWORD;
extern "advapi32" fn RegDeleteTreeW(hKey: usize, lpSubKey: ?[*:0]const u16) callconv(WINAPI) DWORD;

fn msgBox(text: []const u8, caption: []const u8, flags: UINT) i32 {
    var ta: [1024]u16 = undefined;
    var ca: [128]u16 = undefined;
    const tlen = std.unicode.utf8ToUtf16Le(ta[0 .. ta.len - 1], text) catch return 0;
    const clen = std.unicode.utf8ToUtf16Le(ca[0 .. ca.len - 1], caption) catch return 0;
    ta[tlen] = 0;
    ca[clen] = 0;
    return MessageBoxW(null, @ptrCast(&ta), @ptrCast(&ca), flags);
}

fn writeAllBytes(path_w: [*:0]const u16, data: []const u8) !void {
    const h = CreateFileW(path_w, GENERIC_WRITE, 0, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
    if (h == INVALID_HANDLE_VALUE) return error.CreateFileFailed;
    defer _ = CloseHandle(h);
    var written: DWORD = 0;
    var offset: usize = 0;
    while (offset < data.len) {
        const chunk: DWORD = @intCast(@min(data.len - offset, @as(usize, 1024 * 1024)));
        if (WriteFile(h, data.ptr + offset, chunk, &written, null) == 0) return error.WriteFailed;
        offset += written;
    }
}

fn pathJoin(allocator: std.mem.Allocator, a: []const u8, b: []const u8) ![]u8 {
    if (a.len == 0) return try allocator.dupe(u8, b);
    if (a[a.len - 1] == '\\' or a[a.len - 1] == '/') {
        return try std.fmt.allocPrint(allocator, "{s}{s}", .{ a, b });
    }
    return try std.fmt.allocPrint(allocator, "{s}\\{s}", .{ a, b });
}

fn ensureDir(path_utf8: []const u8) void {
    var buf: [MAX_PATH + 1]u16 = undefined;
    const n = std.unicode.utf8ToUtf16Le(buf[0..MAX_PATH], path_utf8) catch return;
    buf[n] = 0;
    _ = CreateDirectoryW(@ptrCast(&buf), null);
}

fn getKnownFolder(csidl: i32, out: *[MAX_PATH]u8) ![]const u8 {
    var wbuf: [MAX_PATH + 1]u16 = undefined;
    const hr = SHGetFolderPathW(null, csidl, null, SHGFP_TYPE_CURRENT, &wbuf);
    if (hr != 0) return error.FolderPathFailed;
    var len: usize = 0;
    while (len < MAX_PATH and wbuf[len] != 0) : (len += 1) {}
    const n = try std.unicode.utf16leToUtf8(out, wbuf[0..len]);
    return out[0..n];
}

fn getEnvPath(name_utf8: []const u8, out: *[MAX_PATH]u8) ![]const u8 {
    var name_w: [64]u16 = undefined;
    const nl = try std.unicode.utf8ToUtf16Le(name_w[0..63], name_utf8);
    name_w[nl] = 0;
    var wbuf: [MAX_PATH + 1]u16 = undefined;
    const got = GetEnvironmentVariableW(@ptrCast(&name_w), &wbuf, MAX_PATH);
    if (got == 0 or got >= MAX_PATH) return error.EnvMissing;
    const n = try std.unicode.utf16leToUtf8(out, wbuf[0..got]);
    return out[0..n];
}

fn writeUtf8File(path_utf8: []const u8, data: []const u8) !void {
    var wbuf: [MAX_PATH + 1]u16 = undefined;
    const n = try std.unicode.utf8ToUtf16Le(wbuf[0..MAX_PATH], path_utf8);
    wbuf[n] = 0;
    try writeAllBytes(@ptrCast(&wbuf), data);
}

fn copySelfTo(dest_utf8: []const u8) !void {
    var self_w: [MAX_PATH + 1]u16 = undefined;
    const glen = GetModuleFileNameW(null, &self_w, MAX_PATH);
    if (glen == 0) return error.GetModuleFailed;
    var dest_w: [MAX_PATH + 1]u16 = undefined;
    const n = try std.unicode.utf8ToUtf16Le(dest_w[0..MAX_PATH], dest_utf8);
    dest_w[n] = 0;
    if (CopyFileW(@ptrCast(&self_w), @ptrCast(&dest_w), FALSE) == 0) return error.CopyFailed;
}

fn regSetString(hKey: usize, name: ?[]const u8, value: []const u8) !void {
    var name_w_buf: [128]u16 = undefined;
    var name_ptr: ?[*:0]const u16 = null;
    if (name) |nm| {
        const nl = try std.unicode.utf8ToUtf16Le(name_w_buf[0..127], nm);
        name_w_buf[nl] = 0;
        name_ptr = @ptrCast(&name_w_buf);
    }
    var val_w: [1024]u16 = undefined;
    const vl = try std.unicode.utf8ToUtf16Le(val_w[0..1023], value);
    val_w[vl] = 0;
    const bytes = (@as(DWORD, @intCast(vl)) + 1) * 2;
    const rc = RegSetValueExW(hKey, name_ptr, 0, REG_SZ, @ptrCast(&val_w), bytes);
    if (rc != ERROR_SUCCESS) return error.RegSetFailed;
}

fn regSetDword(hKey: usize, name: []const u8, value: DWORD) !void {
    var name_w: [128]u16 = undefined;
    const nl = try std.unicode.utf8ToUtf16Le(name_w[0..127], name);
    name_w[nl] = 0;
    var v = value;
    const rc = RegSetValueExW(hKey, @ptrCast(&name_w), 0, REG_DWORD, @ptrCast(&v), 4);
    if (rc != ERROR_SUCCESS) return error.RegSetFailed;
}

fn createUninstallReg(install_dir: []const u8, uninstaller: []const u8, exe_path: []const u8) !void {
    const subkey = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Crush";
    var sub_w: [256]u16 = undefined;
    const sl = try std.unicode.utf8ToUtf16Le(sub_w[0..255], subkey);
    sub_w[sl] = 0;
    var hKey: usize = 0;
    const rc = RegCreateKeyExW(HKEY_CURRENT_USER, @ptrCast(&sub_w), 0, null, REG_OPTION_NON_VOLATILE, KEY_WRITE, null, &hKey, null);
    if (rc != ERROR_SUCCESS) return error.RegCreateFailed;
    defer _ = RegCloseKey(hKey);

    try regSetString(hKey, "DisplayName", PRODUCT_NAME ++ " " ++ PRODUCT_VERSION);
    try regSetString(hKey, "DisplayVersion", PRODUCT_VERSION);
    try regSetString(hKey, "Publisher", PRODUCT_PUBLISHER);
    try regSetString(hKey, "URLInfoAbout", PRODUCT_URL);
    try regSetString(hKey, "InstallLocation", install_dir);
    try regSetString(hKey, "DisplayIcon", exe_path);
    var us_buf: [512]u8 = undefined;
    const us = try std.fmt.bufPrint(&us_buf, "\"{s}\" --uninstall", .{uninstaller});
    try regSetString(hKey, "UninstallString", us);
    try regSetString(hKey, "QuietUninstallString", us);
    try regSetDword(hKey, "NoModify", 1);
    try regSetDword(hKey, "NoRepair", 1);
    try regSetDword(hKey, "EstimatedSize", 80 * 1024);
}

fn createUrlShortcut(path_utf8: []const u8, target_utf8: []const u8, icon_utf8: []const u8) !void {
    var content_buf: [1024]u8 = undefined;
    const content = try std.fmt.bufPrint(&content_buf,
        \\[InternetShortcut]
        \\URL=file:///{s}
        \\IconFile={s}
        \\IconIndex=0
        \\
    , .{ target_utf8, icon_utf8 });
    var fixed: [1024]u8 = undefined;
    var fi: usize = 0;
    for (content) |c| {
        fixed[fi] = if (c == '\\') '/' else c;
        fi += 1;
    }
    try writeUtf8File(path_utf8, fixed[0..fi]);
}

fn registerProtocol(exe_path: []const u8) void {
    const keys = [_][]const u8{
        "Software\\Classes\\roblox",
        "Software\\Classes\\roblox\\shell",
        "Software\\Classes\\roblox\\shell\\open",
        "Software\\Classes\\roblox\\shell\\open\\command",
        "Software\\Classes\\roblox-player",
        "Software\\Classes\\roblox-player\\shell",
        "Software\\Classes\\roblox-player\\shell\\open",
        "Software\\Classes\\roblox-player\\shell\\open\\command",
    };
    for (keys) |k| {
        var kw: [256]u16 = undefined;
        const kl = std.unicode.utf8ToUtf16Le(kw[0..255], k) catch continue;
        kw[kl] = 0;
        var hKey: usize = 0;
        const rc = RegCreateKeyExW(HKEY_CURRENT_USER, @ptrCast(&kw), 0, null, REG_OPTION_NON_VOLATILE, KEY_WRITE, null, &hKey, null);
        if (rc != ERROR_SUCCESS) continue;
        defer _ = RegCloseKey(hKey);
        if (std.mem.endsWith(u8, k, "\\roblox") or std.mem.endsWith(u8, k, "\\roblox-player")) {
            regSetString(hKey, null, "URL:Roblox Protocol") catch {};
            regSetString(hKey, "URL Protocol", "") catch {};
        }
        if (std.mem.endsWith(u8, k, "command")) {
            var cmd_buf: [512]u8 = undefined;
            const cmd = std.fmt.bufPrint(&cmd_buf, "\"{s}\" --deeplink \"%1\"", .{exe_path}) catch continue;
            regSetString(hKey, null, cmd) catch {};
        }
    }
}

fn doInstall(allocator: std.mem.Allocator) !void {
    // Prefer LocalAppData (no admin required)
    var base_buf: [MAX_PATH]u8 = undefined;
    const base = getKnownFolder(CSIDL_LOCAL_APPDATA, &base_buf) catch blk: {
        var env_buf: [MAX_PATH]u8 = undefined;
        break :blk try getEnvPath("LOCALAPPDATA", &env_buf);
    };

    const install_dir = try pathJoin(allocator, base, INSTALL_DIR_NAME);
    defer allocator.free(install_dir);
    const libraries_dir = try pathJoin(allocator, install_dir, "libraries");
    defer allocator.free(libraries_dir);
    const resources_dir = try pathJoin(allocator, install_dir, "resources");
    defer allocator.free(resources_dir);

    ensureDir(install_dir);
    ensureDir(libraries_dir);
    ensureDir(resources_dir);

    const exe_path = try pathJoin(allocator, install_dir, EXE_NAME);
    defer allocator.free(exe_path);
    const uninstaller_path = try pathJoin(allocator, install_dir, UNINSTALLER_NAME);
    defer allocator.free(uninstaller_path);
    const icon_path = try pathJoin(allocator, install_dir, "icon.ico");
    defer allocator.free(icon_path);
    const bat_path = try pathJoin(allocator, install_dir, "open_game.bat");
    defer allocator.free(bat_path);
    const vcr_path = try pathJoin(allocator, libraries_dir, "vcruntime140.dll");
    defer allocator.free(vcr_path);
    const vcr1_path = try pathJoin(allocator, libraries_dir, "vcruntime140_1.dll");
    defer allocator.free(vcr1_path);
    const readme_path = try pathJoin(allocator, install_dir, "README.txt");
    defer allocator.free(readme_path);
    const version_path = try pathJoin(allocator, install_dir, "version.txt");
    defer allocator.free(version_path);

    try writeUtf8File(icon_path, icon_bytes);
    try writeUtf8File(bat_path, open_game_bat);
    try writeUtf8File(vcr_path, vcruntime140);
    try writeUtf8File(vcr1_path, vcruntime140_1);
    try writeUtf8File(readme_path, launcher_note);
    try writeUtf8File(version_path, PRODUCT_VERSION ++ "\n");
    try copySelfTo(exe_path);
    try copySelfTo(uninstaller_path);

    var sm_buf: [MAX_PATH]u8 = undefined;
    if (getKnownFolder(CSIDL_STARTMENU, &sm_buf)) |sm| {
        const programs = try pathJoin(allocator, sm, "Programs");
        defer allocator.free(programs);
        ensureDir(programs);
        const crush_sm = try pathJoin(allocator, programs, INSTALL_DIR_NAME);
        defer allocator.free(crush_sm);
        ensureDir(crush_sm);
        const lnk = try pathJoin(allocator, crush_sm, "Crush.url");
        defer allocator.free(lnk);
        createUrlShortcut(lnk, exe_path, icon_path) catch {};
        const ulnk = try pathJoin(allocator, crush_sm, "Uninstall Crush.url");
        defer allocator.free(ulnk);
        createUrlShortcut(ulnk, uninstaller_path, icon_path) catch {};
    } else |_| {}

    var desk_buf: [MAX_PATH]u8 = undefined;
    if (getKnownFolder(CSIDL_DESKTOPDIRECTORY, &desk_buf)) |desk| {
        const dlnk = try pathJoin(allocator, desk, "Crush.url");
        defer allocator.free(dlnk);
        createUrlShortcut(dlnk, exe_path, icon_path) catch {};
    } else |_| {}

    try createUninstallReg(install_dir, uninstaller_path, exe_path);
    registerProtocol(exe_path);

    const done_msg = try std.fmt.allocPrint(
        allocator,
        "Crush {s} was installed successfully.\n\nLocation:\n{s}\n\nShortcuts were added to the Start Menu and Desktop.",
        .{ PRODUCT_VERSION, install_dir },
    );
    defer allocator.free(done_msg);
    _ = msgBox(done_msg, "Crush Setup", MB_OK | MB_ICONINFORMATION);
}

fn deletePath(path_utf8: []const u8) void {
    var wbuf: [MAX_PATH + 1]u16 = undefined;
    const n = std.unicode.utf8ToUtf16Le(wbuf[0..MAX_PATH], path_utf8) catch return;
    wbuf[n] = 0;
    _ = DeleteFileW(@ptrCast(&wbuf));
    _ = RemoveDirectoryW(@ptrCast(&wbuf));
}

fn doUninstall(allocator: std.mem.Allocator) !void {
    const answer = msgBox("Remove Crush from this computer?", "Uninstall Crush", MB_YESNO | MB_ICONQUESTION);
    if (answer != IDYES) return;

    var base_buf: [MAX_PATH]u8 = undefined;
    const base = getKnownFolder(CSIDL_LOCAL_APPDATA, &base_buf) catch blk: {
        var env_buf: [MAX_PATH]u8 = undefined;
        break :blk (getEnvPath("LOCALAPPDATA", &env_buf) catch "C:\\Users\\Public");
    };
    const install_dir = try pathJoin(allocator, base, INSTALL_DIR_NAME);
    defer allocator.free(install_dir);

    const files = [_][]const u8{
        "crush.exe",
        "icon.ico",
        "open_game.bat",
        "README.txt",
        "version.txt",
        "Uninstall Crush.exe",
        "libraries\\vcruntime140.dll",
        "libraries\\vcruntime140_1.dll",
    };
    for (files) |f| {
        const p = try pathJoin(allocator, install_dir, f);
        defer allocator.free(p);
        deletePath(p);
    }
    const libs = try pathJoin(allocator, install_dir, "libraries");
    defer allocator.free(libs);
    const res = try pathJoin(allocator, install_dir, "resources");
    defer allocator.free(res);
    deletePath(libs);
    deletePath(res);
    deletePath(install_dir);

    const subkey = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Crush";
    var sub_w: [256]u16 = undefined;
    const sl = try std.unicode.utf8ToUtf16Le(sub_w[0..255], subkey);
    sub_w[sl] = 0;
    _ = RegDeleteTreeW(HKEY_CURRENT_USER, @ptrCast(&sub_w));

    _ = msgBox("Crush has been removed.", "Uninstall Crush", MB_OK | MB_ICONINFORMATION);
}

fn hasArg(argv: []const []const u8, flag: []const u8) bool {
    for (argv) |a| {
        if (std.ascii.eqlIgnoreCase(a, flag)) return true;
    }
    return false;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arg_it = try std.process.argsWithAllocator(allocator);
    defer arg_it.deinit();
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();
    while (arg_it.next()) |a| {
        try args.append(a);
    }

    if (hasArg(args.items, "--uninstall") or hasArg(args.items, "/uninstall") or hasArg(args.items, "--remove")) {
        try doUninstall(allocator);
        return;
    }

    const silent = hasArg(args.items, "/S") or hasArg(args.items, "--silent") or hasArg(args.items, "/silent");
    if (!silent) {
        const intro = try std.fmt.allocPrint(allocator,
            \\Crush {s} Setup
            \\
            \\This will install Crush (Roblox bootstrapper) on your computer.
            \\
            \\Publisher: {s}
            \\Install location: %LocalAppData%\Crush
            \\
            \\Click OK to continue.
        , .{ PRODUCT_VERSION, PRODUCT_PUBLISHER });
        defer allocator.free(intro);
        const r = msgBox(intro, "Crush Setup", MB_OKCANCEL | MB_ICONINFORMATION);
        if (r == IDCANCEL) return;
    }

    doInstall(allocator) catch |err| {
        var buf: [256]u8 = undefined;
        const m = std.fmt.bufPrint(&buf, "Installation failed: {s}", .{@errorName(err)}) catch "Installation failed.";
        _ = msgBox(m, "Crush Setup", MB_OK | MB_ICONERROR);
        return err;
    };
}
