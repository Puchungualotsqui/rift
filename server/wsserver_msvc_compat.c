#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#pragma comment(linker, "/NODEFAULTLIB:MSVCRT")

void wsserver_compat_link(void *mutex_lock, void *mutex_unlock, void *mutex_init,
    void *mutex_destroy, void *condition_init, void *condition_destroy,
    void *condition_timedwait, void *condition_signal, void *thread_create,
    void *thread_detach, void *thread_join, void *clock_gettime) {
    void * volatile symbols[12];
    symbols[0] = mutex_lock;
    symbols[1] = mutex_unlock;
    symbols[2] = mutex_init;
    symbols[3] = mutex_destroy;
    symbols[4] = condition_init;
    symbols[5] = condition_destroy;
    symbols[6] = condition_timedwait;
    symbols[7] = condition_signal;
    symbols[8] = thread_create;
    symbols[9] = thread_detach;
    symbols[10] = thread_join;
    symbols[11] = clock_gettime;
}

int __mingw_snprintf(char *buffer, size_t count, const char *format, ...) {
    int result;
    va_list args;
    va_start(args, format);
    result = vsnprintf(buffer, count, format, args);
    va_end(args);
    return result;
}

static int wsserver_is_delimiter(char value, const char *delimiters) {
    while (*delimiters) {
        if (value == *delimiters) return 1;
        delimiters++;
    }
    return 0;
}

char *strtok_r(char *string, const char *delimiters, char **context) {
    char *token = string != NULL ? string : *context;
    if (token == NULL) return NULL;

    while (*token && wsserver_is_delimiter(*token, delimiters)) token++;
    if (*token == '\0') {
        *context = NULL;
        return NULL;
    }

    char *end = token;
    while (*end && !wsserver_is_delimiter(*end, delimiters)) end++;
    if (*end) {
        *end = '\0';
        *context = end + 1;
    } else {
        *context = NULL;
    }
    return token;
}

int strncasecmp(const char *left, const char *right, size_t count) {
    return _strnicmp(left, right, count);
}
