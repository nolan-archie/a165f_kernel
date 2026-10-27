#ifndef __KSU_H_APP_PROFILE
#define __KSU_H_APP_PROFILE

#include "uapi/app_profile.h"

#define TIF_KSU_DISABLE_ESCAPE_WITH_ROOT 63

// Escalate current process to root with the appropriate profile
int escape_with_root_profile(void);

/* Escalate the current internal context even if it is already root. */
void escape_to_root_forced(void);

void escape_to_root_for_init(void);

#endif
