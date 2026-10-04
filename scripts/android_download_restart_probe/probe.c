#define _GNU_SOURCE
#include <dlfcn.h>
#include <jni.h>
#include <stdint.h>

// These read-only addresses are passed by the version/SHA-pinned Python runner.
JNIEXPORT jint JNICALL Java_DownloadProbe_flag(JNIEnv *env, jclass klass, jstring path) {
    (void)klass;
    const char *name = (*env)->GetStringUTFChars(env, path, NULL);
    if (name == NULL) return -4;
    void *handle = dlopen(name, RTLD_NOW | RTLD_NOLOAD);
    (*env)->ReleaseStringUTFChars(env, path, name);
    if (handle == NULL) return -1;

    void *symbol = dlsym(handle, "Java_opensource_jenny_Jni_invoke");
    Dl_info info;
    if (symbol == NULL || dladdr(symbol, &info) == 0) {
        dlclose(handle);
        return -2;
    }
    const volatile uint8_t *base = (const volatile uint8_t *)info.dli_fbase;
    int initialized = base[RESTART_INITIALIZED_VA];
    int flag = initialized == 2 ? base[RESTART_FLAG_VA] : -3;
    dlclose(handle);
    return flag;
}
