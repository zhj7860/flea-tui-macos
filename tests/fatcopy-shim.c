// Test-only vfat model at the libc boundary for every path under FLEA_TEST_FAT_ROOT, driven by tests/fatcopy.sh.
#define _GNU_SOURCE
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <unistd.h>

#define VFAT_MAGIC 0x4D44
#define FD_PREFIX "/proc/self/fd/"

// Sample input: /proc/self/fd/7/a.txt with fd 7 open on /x/out answers /x/out/a.txt, the way the copy names a child.
static int resolve(const char *path, char *out, size_t n) {
    size_t pre = strlen(FD_PREFIX);
    if (strncmp(path, FD_PREFIX, pre) != 0) {
        snprintf(out, n, "%s", path);
        return 0;
    }
    const char *num = path + pre;
    const char *slash = strchr(num, '/');
    int digits = slash ? (int)(slash - num) : (int)strlen(num);
    char link[64];
    snprintf(link, sizeof link, FD_PREFIX "%.*s", digits, num);
    ssize_t len = readlink(link, out, n - 1);
    if (len < 0)
        return -1;
    out[len] = 0;
    if (slash)
        strncat(out, slash, n - strlen(out) - 1);
    return 0;
}

// Whole components only, so /x/fatter is not under /x/fat.
static int under(const char *path, char *real, size_t n) {
    const char *root = getenv("FLEA_TEST_FAT_ROOT");
    if (!root || !*root || !path || resolve(path, real, n) != 0)
        return 0;
    size_t rl = strlen(root);
    return strncmp(real, root, rl) == 0 && (real[rl] == '/' || real[rl] == 0);
}

static const char *leaf_of(const char *path) {
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

// The characters vfat refuses in a long name, the ones fsname.rs names.
static int refused_name(const char *real) {
    return strpbrk(leaf_of(real), "\"*:<>?\\|") != NULL;
}

// vfat folds case, so a create whose name another entry holds in any case finds it taken.
static int folded_taken(const char *real) {
    char parent[PATH_MAX];
    snprintf(parent, sizeof parent, "%s", real);
    char *slash = strrchr(parent, '/');
    if (!slash)
        return 0;
    *slash = 0;
    const char *leaf = leaf_of(real);
    DIR *dir = opendir(parent);
    if (!dir)
        return 0;
    int taken = 0;
    struct dirent *entry;
    while (!taken && (entry = readdir(dir)) != NULL)
        taken = strcasecmp(entry->d_name, leaf) == 0;
    closedir(dir);
    return taken;
}

// Sample input: a create of /fat/x/a:b.txt answers EINVAL, of /fat/x/README when readme exists answers EEXIST.
static int create_refusal(const char *path) {
    char real[PATH_MAX];
    if (!under(path, real, sizeof real))
        return 0;
    if (refused_name(real))
        return EINVAL;
    if (folded_taken(real))
        return EEXIST;
    return 0;
}

static int refuse(int code) {
    errno = code;
    return -1;
}

int symlink(const char *target, const char *linkpath) {
    char real[PATH_MAX];
    if (under(linkpath, real, sizeof real))
        return refuse(EPERM);
    int (*next)(const char *, const char *) = dlsym(RTLD_NEXT, "symlink");
    return next(target, linkpath);
}

int mknod(const char *path, mode_t mode, dev_t dev) {
    char real[PATH_MAX];
    if (under(path, real, sizeof real))
        return refuse(EPERM);
    int (*next)(const char *, mode_t, dev_t) = dlsym(RTLD_NEXT, "mknod");
    return next(path, mode, dev);
}

int mkdir(const char *path, mode_t mode) {
    int code = create_refusal(path);
    if (code)
        return refuse(code);
    int (*next)(const char *, mode_t) = dlsym(RTLD_NEXT, "mkdir");
    return next(path, mode);
}

static int open_with(const char *name, const char *path, int flags, mode_t mode) {
    if ((flags & O_CREAT) && (flags & O_EXCL)) {
        int code = create_refusal(path);
        if (code)
            return refuse(code);
    }
    int (*next)(const char *, int, ...) = dlsym(RTLD_NEXT, name);
    return next(path, flags, mode);
}

int open(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & (O_CREAT | O_TMPFILE)) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return open_with("open", path, flags, mode);
}

int open64(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & (O_CREAT | O_TMPFILE)) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return open_with("open64", path, flags, mode);
}

// A rename onto the model crosses a filesystem, which is what sends a move down its copy path.
int renameat2(int olddirfd, const char *oldpath, int newdirfd, const char *newpath, unsigned int flags) {
    char real[PATH_MAX];
    if (newdirfd == AT_FDCWD && under(newpath, real, sizeof real) && !under(oldpath, real, sizeof real))
        return refuse(EXDEV);
    int (*next)(int, const char *, int, const char *, unsigned int) = dlsym(RTLD_NEXT, "renameat2");
    return next(olddirfd, oldpath, newdirfd, newpath, flags);
}

int statfs(const char *path, struct statfs *buf) {
    int (*next)(const char *, struct statfs *) = dlsym(RTLD_NEXT, "statfs");
    int rc = next(path, buf);
    char real[PATH_MAX];
    if (rc == 0 && under(path, real, sizeof real))
        buf->f_type = VFAT_MAGIC;
    return rc;
}
