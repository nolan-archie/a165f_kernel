###############################################################################
# Necessary Check

ifneq ($(KERNEL_OUT),)
    ccflags-y += -imacros $(KERNEL_OUT)/include/generated/autoconf.h
endif

ifndef TOP
    TOP := $(srctree)/..
endif

# Override MODULE_NAME to ensure adaptor builds as wmt_chrdev_wifi.ko
# (parent Makefile exports MODULE_NAME=wlan_drv_gen4m_6789 for WLAN driver,
#  but adaptor must always use wmt_chrdev_wifi)
MODULE_NAME := wmt_chrdev_wifi

# Force build fail on modpost warning
KBUILD_MODPOST_FAIL_ON_WARNINGS := y

# Add adaptor's own include path FIRST to ensure adaptor headers are found
# This must come before other include paths to avoid conflicts with mgmt/wlan_ring.h
# Prepend to existing ccflags-y (from parent's subdir-ccflags-y) to ensure priority
# Note: subdir-ccflags-y from parent is processed separately, so we need to ensure
# adaptor path comes first in the final command line by prepending here
ccflags-y := -I$(TOP)/vendor/mediatek/kernel_modules/connectivity/wlan/adaptor/include $(ccflags-y)

ccflags-y += \
    -I$(srctree)/drivers/misc/mediatek/include/mt-plat \
    -I$(TOP)/vendor/mediatek/kernel_modules/connectivity/common/common_main/include \
    -I$(TOP)/vendor/mediatek/kernel_modules/connectivity/common/common_main/linux/include

ifeq ($(CONNAC_VER), 2_0)
ccflags-y += -I$(TOP)/vendor/mediatek/kernel_modules/connectivity/conninfra/include
ccflags-y += -I$(TOP)/vendor/mediatek/kernel_modules/connectivity/conninfra/debug_utility
ccflags-y += -I$(TOP)/vendor/mediatek/kernel_modules/connectivity/conninfra/debug_utility/include
ccflags-y += -I$(TOP)/vendor/mediatek/kernel_modules/connectivity/conninfra/debug_utility/connsyslog
ccflags-y += -I$(TOP)/vendor/mediatek/kernel_modules/connectivity/conninfra/debug_utility/coredump
endif

ifneq ($(CONFIG_MTK_CONNSYS_DEDICATED_LOG_PATH),)
ccflags-y += -DCONFIG_MTK_CONNSYS_DEDICATED_LOG_PATH
ccflags-y += -I$(TOP)/vendor/mediatek/kernel_modules/connectivity/common/debug_utility
# Note: -I$(src)/include is already added unconditionally above
endif

ifeq ($(CONFIG_MTK_CONN_LTE_IDC_SUPPORT),y)
    ccflags-y += -DWMT_IDC_SUPPORT=1
else
    ccflags-y += -DWMT_IDC_SUPPORT=0
endif

ifeq ($(CONNAC_VER), 2_0)
ccflags-y += -DCFG_ANDORID_CONNINFRA_SUPPORT=1
ccflags-y += -DCFG_ANDORID_CONNINFRA_COREDUMP_SUPPORT=1
else
ccflags-y += -DCFG_ANDORID_CONNINFRA_SUPPORT=0
ccflags-y += -DCFG_ANDORID_CONNINFRA_COREDUMP_SUPPORT=0
endif

ifeq ($(CONFIG_MTK_TC10_FEATURE), y)
    ccflags-y += -DCFG_TC10_FEATURE=1
else
    ccflags-y += -DCFG_TC10_FEATURE=0
endif

ccflags-y += -D MTK_WCN_WMT_STP_EXP_SYMBOL_ABSTRACT

ccflags-y += -D CREATE_NODE_DYNAMIC=1

ifeq ($(CONFIG_WLAN_DRV_BUILD_IN),y)
$(warning $(MODULE_NAME) build-in boot.img)
obj-y += $(MODULE_NAME).o
else
$(warning $(MODULE_NAME) is kernel module)
obj-m += $(MODULE_NAME).o
endif

# Wi-Fi character device driver
$(MODULE_NAME)-objs += wmt_cdev_wifi.o
ifneq ($(CONFIG_MTK_CONNSYS_DEDICATED_LOG_PATH),)
$(MODULE_NAME)-objs += fw_log_wifi.o
$(MODULE_NAME)-objs += fw_log_ics.o
$(MODULE_NAME)-objs += wlan_ring.o
endif
ifeq ($(CONNAC_VER), 2_0)
$(MODULE_NAME)-objs += wifi_pwr_on.o
endif
