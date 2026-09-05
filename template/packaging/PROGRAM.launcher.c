#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef OG_PROGRAM
#error OG_PROGRAM must name the packaged executable
#endif

#ifndef OG_STATIC_PREFIX
#define OG_STATIC_PREFIX ""
#endif

typedef const char *(*libroot_prefix_function)(void);

static int join_path(char output[PATH_MAX], const char *prefix, const char *suffix) {
    int length = snprintf(output, PATH_MAX, "%s%s", prefix, suffix);
    return length > 0 && length < PATH_MAX;
}

static const char *bootstrap_prefix(void) {
    static char resolved[PATH_MAX];
    const char *configured = OG_STATIC_PREFIX;
    if (configured[0] != '\0') return configured;

    void *handle = dlopen("@executable_path/../lib/libroot.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!handle) return NULL;
    libroot_prefix_function get_prefix =
        (libroot_prefix_function)dlsym(handle, "libroot_get_jbroot_prefix");
    if (!get_prefix) return NULL;
    const char *prefix = get_prefix();
    if (!prefix || prefix[0] != '/') return NULL;
    size_t length = strlen(prefix);
    while (length > 1 && prefix[length - 1] == '/') length--;
    if (length >= sizeof(resolved)) return NULL;
    memcpy(resolved, prefix, length);
    resolved[length] = '\0';
    return resolved;
}

static void prepend_bootstrap_path(const char *prefix) {
    const char *current = getenv("PATH");
    char *value = NULL;
    int length = asprintf(
        &value,
        "%s/usr/local/bin:%s/usr/bin:%s/bin:%s/usr/sbin:%s/sbin%s%s",
        prefix, prefix, prefix, prefix, prefix,
        current && current[0] ? ":" : "",
        current && current[0] ? current : ""
    );
    if (length < 0 || !value) return;
    (void)setenv("PATH", value, 1);
    free(value);
}

static void translate_shell(const char *prefix) {
    const char *shell = getenv("SHELL");
    if (!shell) return;
    if (strncmp(shell, "/bin/", 5) != 0 && strncmp(shell, "/usr/bin/", 9) != 0) return;
    char path[PATH_MAX];
    if (join_path(path, prefix, shell)) (void)setenv("SHELL", path, 1);
}

static void set_default_paths(const char *prefix) {
    char path[PATH_MAX];
    if (!getenv("SSL_CERT_FILE")) {
        static const char *certificates[] = {
            "/etc/ssl/cert.pem",
            "/etc/ssl/certs/ca-certificates.crt",
        };
        for (size_t index = 0; index < sizeof(certificates) / sizeof(certificates[0]); index++) {
            if (join_path(path, prefix, certificates[index]) && access(path, R_OK) == 0) {
                (void)setenv("SSL_CERT_FILE", path, 1);
                break;
            }
        }
    }
    if (!getenv("BROWSER") && join_path(path, prefix, "/usr/bin/uiopen") && access(path, X_OK) == 0)
        (void)setenv("BROWSER", path, 1);
}

int main(int argc, char **argv) {
    (void)argc;
    const char *prefix = bootstrap_prefix();
    if (!prefix) {
        fprintf(stderr, "%s: cannot resolve the jailbreak bootstrap with libroot\n", OG_PROGRAM);
        return 127;
    }
    prepend_bootstrap_path(prefix);
    translate_shell(prefix);
    set_default_paths(prefix);

    char executable[PATH_MAX];
    if (!join_path(executable, prefix, "/usr/libexec/" OG_PROGRAM "/" OG_PROGRAM)) {
        fprintf(stderr, "%s: bootstrap path is too long\n", OG_PROGRAM);
        return 127;
    }
    argv[0] = executable;
    execv(executable, argv);
    int error = errno;
    fprintf(stderr, "%s: cannot execute %s: %s\n", OG_PROGRAM, executable, strerror(error));
    return error == ENOENT ? 127 : 126;
}
