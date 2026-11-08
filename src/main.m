// sidebarctl — manage the macOS Finder sidebar "Favorites" from the command line.
//
// Derived from mysides (https://github.com/mosen/mysides), MIT License,
// Copyright (c) 2016 Mosen; "portions (l) copyleft 2011 Adam Strzelecki nanoant.com"
// (as noted in the upstream source and LICENSE).
// Modifications Copyright (c) 2026 Abhiraj Doad. See LICENSE.
//
// Uses the LSSharedFileList API. Apple deprecated it in macOS 10.11 but, as of
// macOS 26 (Tahoe), it still reads and writes the Finder sidebar Favorites list.

#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>

#ifndef SIDEBARCTL_VERSION
#define SIDEBARCTL_VERSION "dev"
#endif

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

enum { EXIT_OK = 0, EXIT_FAIL = 1, EXIT_USAGE = 2, EXIT_API = 3 };

static void print_usage(FILE *out) {
    fprintf(out,
        "sidebarctl %s — manage Finder sidebar Favorites\n\n"
        "Usage:\n"
        "  sidebarctl list [--json]                 List Favorites (name and location)\n"
        "  sidebarctl add <folder> [--name NAME] [--top] [--force]\n"
        "                                           Add a folder (skipped if already present)\n"
        "  sidebarctl remove <name|path>            Remove the first matching item\n"
        "  sidebarctl contains <path>               Exit 0 if the path is in Favorites, else 1\n"
        "  sidebarctl version                       Print version\n"
        "  sidebarctl help                          Show this help\n\n"
        "<path> may be a filesystem path (~ and relative paths are expanded) or a file:// URL.\n"
        "list prints one item per line: NAME<TAB>PATH.\n"
        "Exit codes: 0 ok, 1 not found, 2 usage error (incl. missing path), 3 macOS API error.\n",
        SIDEBARCTL_VERSION);
}

// Resolve a user-supplied path or file:// URL into a standardized URL.
// mustBeDir: the path must exist and be a directory (used by `add`).
static NSURL *url_from_arg(const char *arg, BOOL mustBeDir, NSString **err) {
    NSString *s = arg ? [NSString stringWithUTF8String:arg] : nil;
    if (!s || s.length == 0) { if (err) *err = @"empty or non-UTF-8 path"; return nil; }
    NSURL *url = nil;
    if ([s hasPrefix:@"file://"]) {
        // Accept encoded (%20) and raw (spaces, unicode) forms alike: decode, then treat as a path.
        NSString *rest = [s substringFromIndex:7];
        if ([rest hasPrefix:@"localhost/"]) rest = [rest substringFromIndex:9];
        NSString *decoded = [rest stringByRemovingPercentEncoding];
        if (!decoded || ![decoded hasPrefix:@"/"]) { if (err) *err = @"invalid file:// URL (expected file:///absolute/path)"; return nil; }
        url = [NSURL fileURLWithPath:[decoded stringByStandardizingPath] isDirectory:YES];
    } else {
        NSString *p = [[s stringByExpandingTildeInPath] stringByStandardizingPath];
        if (![p isAbsolutePath]) p = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:p];
        url = [NSURL fileURLWithPath:[p stringByStandardizingPath] isDirectory:YES];
    }
    url = [url URLByStandardizingPath];
    if (mustBeDir) {
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDir]) {
            if (err) *err = [NSString stringWithFormat:@"no such folder: %@", url.path];
            return nil;
        }
        if (!isDir) {
            if (err) *err = [NSString stringWithFormat:@"not a folder: %@", url.path];
            return nil;
        }
    }
    return url;
}

static NSString *norm_path(NSURL *u) {
    // Collapse "//", ".", ".." and the /private alias so paths and file:// URLs compare equal.
    NSString *p = [[[u URLByStandardizingPath] path] stringByStandardizingPath];
    while (p.length > 1 && [p hasSuffix:@"/"]) p = [p substringToIndex:p.length - 1];
    return p;
}

static LSSharedFileListRef open_favorites(void) {
    return LSSharedFileListCreate(kCFAllocatorDefault, kLSSharedFileListFavoriteItems, NULL);
}

// Snapshot of favorites as an array of dictionaries: name, url (may be nil), item (bridged ref).
static NSArray<NSDictionary *> *snapshot(LSSharedFileListRef list) {
    UInt32 seed = 0;
    NSArray *items = CFBridgingRelease(LSSharedFileListCopySnapshot(list, &seed));
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:items.count];
    for (id obj in items) {
        LSSharedFileListItemRef item = (__bridge LSSharedFileListItemRef)obj;
        NSString *name = CFBridgingRelease(LSSharedFileListItemCopyDisplayName(item)) ?: @"";
        CFURLRef cfurl = LSSharedFileListItemCopyResolvedURL(item,
            kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes, NULL);
        NSURL *url = cfurl ? CFBridgingRelease(cfurl) : nil;
        NSMutableDictionary *d = [@{ @"name": name, @"item": obj } mutableCopy];
        if (url) d[@"url"] = url;
        [out addObject:d];
    }
    return out;
}

static NSDictionary *find_by_url(NSArray<NSDictionary *> *snap, NSURL *url) {
    NSString *want = norm_path(url);
    for (NSDictionary *d in snap) {
        NSURL *u = d[@"url"];
        if (u && [norm_path(u) isEqualToString:want]) return d;
    }
    return nil;
}

static int cmd_list(BOOL json) {
    LSSharedFileListRef list = open_favorites();
    if (!list) { fprintf(stderr, "error: cannot open the Finder sidebar list\n"); return EXIT_API; }
    NSArray *snap = snapshot(list);
    if (json) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *d in snap) {
            NSURL *u = d[@"url"];
            [rows addObject:@{ @"name": d[@"name"], @"path": u ? norm_path(u) : [NSNull null],
                               @"url": u ? u.absoluteString : [NSNull null] }];
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:rows
            options:NSJSONWritingPrettyPrinted | NSJSONWritingWithoutEscapingSlashes error:nil];
        fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout);
    } else {
        for (NSDictionary *d in snap) {
            NSURL *u = d[@"url"];
            printf("%s\t%s\n", [d[@"name"] UTF8String], u ? norm_path(u).UTF8String : "(unresolved)");
        }
    }
    CFRelease(list);
    return EXIT_OK;
}

static int cmd_contains(const char *arg) {
    NSString *err = nil;
    NSURL *url = url_from_arg(arg, NO, &err);
    if (!url) { fprintf(stderr, "error: %s\n", err.UTF8String); return EXIT_USAGE; }
    LSSharedFileListRef list = open_favorites();
    if (!list) { fprintf(stderr, "error: cannot open the Finder sidebar list\n"); return EXIT_API; }
    BOOL found = find_by_url(snapshot(list), url) != nil;
    CFRelease(list);
    return found ? EXIT_OK : EXIT_FAIL;
}

static int cmd_add(const char *arg, NSString *name, BOOL top, BOOL force) {
    NSString *err = nil;
    NSURL *url = url_from_arg(arg, YES, &err);
    if (!url) { fprintf(stderr, "error: %s\n", err.UTF8String); return EXIT_USAGE; }
    LSSharedFileListRef list = open_favorites();
    if (!list) { fprintf(stderr, "error: cannot open the Finder sidebar list\n"); return EXIT_API; }
    if (!force && find_by_url(snapshot(list), url)) {
        printf("already in sidebar: %s\n", norm_path(url).UTF8String);
        CFRelease(list);
        return EXIT_OK;
    }
    NSString *display = name ?: url.lastPathComponent;
    LSSharedFileListItemRef added = LSSharedFileListInsertItemURL(list,
        top ? kLSSharedFileListItemBeforeFirst : kLSSharedFileListItemLast,
        (__bridge CFStringRef)display, NULL, (__bridge CFURLRef)url, NULL, NULL);
    if (!added) {
        fprintf(stderr, "error: macOS refused to add %s\n", norm_path(url).UTF8String);
        CFRelease(list);
        return EXIT_API;
    }
    CFRelease(added);
    BOOL ok = find_by_url(snapshot(list), url) != nil;
    CFRelease(list);
    if (!ok) { fprintf(stderr, "error: add reported success but the item is not listed\n"); return EXIT_API; }
    printf("added: %s (%s)\n", display.UTF8String, norm_path(url).UTF8String);
    return EXIT_OK;
}

static int cmd_remove(const char *arg) {
    LSSharedFileListRef list = open_favorites();
    if (!list) { fprintf(stderr, "error: cannot open the Finder sidebar list\n"); return EXIT_API; }
    NSArray *snap = snapshot(list);
    NSString *s = [NSString stringWithUTF8String:arg];
    NSDictionary *hit = nil;
    for (NSDictionary *d in snap) if ([d[@"name"] isEqualToString:s]) { hit = d; break; }
    if (!hit) {
        NSURL *url = url_from_arg(arg, NO, NULL);
        if (url) hit = find_by_url(snap, url);
    }
    if (!hit) {
        fprintf(stderr, "not found in sidebar: %s\n", arg);
        CFRelease(list);
        return EXIT_FAIL;
    }
    OSStatus st = LSSharedFileListItemRemove(list, (__bridge LSSharedFileListItemRef)hit[@"item"]);
    CFRelease(list);
    if (st != noErr) { fprintf(stderr, "error: macOS refused to remove item (OSStatus %d)\n", (int)st); return EXIT_API; }
    printf("removed: %s\n", [hit[@"name"] UTF8String]);
    return EXIT_OK;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { print_usage(stderr); return EXIT_USAGE; }
        const char *cmd = argv[1];

        if (!strcmp(cmd, "help") || !strcmp(cmd, "-h") || !strcmp(cmd, "--help")) { print_usage(stdout); return EXIT_OK; }
        if (!strcmp(cmd, "version") || !strcmp(cmd, "--version")) {
            if (argc != 2) { fprintf(stderr, "usage: sidebarctl version\n"); return EXIT_USAGE; }
            printf("sidebarctl %s\n", SIDEBARCTL_VERSION); return EXIT_OK;
        }

        if (!strcmp(cmd, "list")) {
            if (argc > 3 || (argc == 3 && strcmp(argv[2], "--json"))) { fprintf(stderr, "usage: sidebarctl list [--json]\n"); return EXIT_USAGE; }
            return cmd_list(argc == 3);
        }
        if (!strcmp(cmd, "contains")) {
            if (argc != 3) { fprintf(stderr, "usage: sidebarctl contains <path>\n"); return EXIT_USAGE; }
            return cmd_contains(argv[2]);
        }
        if (!strcmp(cmd, "remove")) {
            if (argc != 3 || !argv[2][0]) { fprintf(stderr, "usage: sidebarctl remove <name|path>\n"); return EXIT_USAGE; }
            return cmd_remove(argv[2]);
        }
        if (!strcmp(cmd, "add")) {
            const char *path = NULL; NSString *name = nil; BOOL top = NO, force = NO;
            for (int i = 2; i < argc; i++) {
                if (!strcmp(argv[i], "--top")) top = YES;
                else if (!strcmp(argv[i], "--force")) force = YES;
                else if (!strcmp(argv[i], "--name")) {
                    if (++i >= argc || !argv[i][0] || !strncmp(argv[i], "--", 2)) { fprintf(stderr, "error: --name needs a non-empty value\n"); return EXIT_USAGE; }
                    name = [NSString stringWithUTF8String:argv[i]];
                    if (!name) { fprintf(stderr, "error: --name must be valid UTF-8\n"); return EXIT_USAGE; }
                } else if (!strncmp(argv[i], "--", 2)) { fprintf(stderr, "error: unknown option: %s\n", argv[i]); return EXIT_USAGE; }
                else if (!path) path = argv[i];
                else { fprintf(stderr, "error: unexpected argument: %s\n", argv[i]); return EXIT_USAGE; }
            }
            if (!path) { fprintf(stderr, "usage: sidebarctl add <path> [--name NAME] [--top] [--force]\n"); return EXIT_USAGE; }
            return cmd_add(path, name, top, force);
        }
        fprintf(stderr, "unknown command: %s\n\n", cmd);
        print_usage(stderr);
        return EXIT_USAGE;
    }
}

#pragma clang diagnostic pop
