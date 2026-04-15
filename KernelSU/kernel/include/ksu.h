#ifndef __KSU_H_KSU_INCLUDE
#define __KSU_H_KSU_INCLUDE

#include <linux/workqueue.h>

#include "../ksu.h"

static inline int startswith(char *s, char *prefix)
{
    return strncmp(s, prefix, strlen(prefix));
}

static inline int endswith(const char *s, const char *t)
{
    size_t slen = strlen(s);
    size_t tlen = strlen(t);
    if (tlen > slen)
        return 1;
    return strcmp(s + slen - tlen, t);
}

#endif
