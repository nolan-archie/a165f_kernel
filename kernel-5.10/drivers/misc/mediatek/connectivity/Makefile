#
# Copyright (C) 2015 MediaTek Inc.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#

# Connectivity combo driver
# If KERNELRELEASE is defined, we've been invoked from the
# kernel build system and can use its language.

ifndef TOP
    TOP := $(srctree)/..
endif

ifneq ($(KERNELRELEASE),)
    subdir-ccflags-y += -I$(srctree)/
    subdir-ccflags-y += -I$(srctree)/drivers/misc/mediatek/base/power/include
    subdir-ccflags-y += -I$(srctree)/drivers/misc/mediatek/clkbuf/src
    subdir-ccflags-y += -Werror -I$(srctree)/drivers/misc/mediatek/include/mt-plat
    subdir-ccflags-y += -I$(srctree)/drivers/mmc/core
    subdir-ccflags-y += -I$(srctree)/drivers/misc/mediatek/eccci/
    subdir-ccflags-y += -I$(srctree)/drivers/clk/mediatek/
    subdir-ccflags-y += -I$(srctree)/drivers/pinctrl/mediatek/
    subdir-ccflags-y += -I$(srctree)/drivers/misc/mediatek/power_throttling/

    #ifneq ($(CONFIG_MTK_TINYSYS_SCP_SUPPORT),)
        # SCP
    #    subdir-ccflags-y += -Werror -I$(srctree)/drivers/misc/mediatek/scp/include
    #    subdir-ccflags-y += -Werror -I$(srctree)/drivers/misc/mediatek/connectivity/conap_scp

        # Aoltest
    #    ifeq ($(CONFIG_MTK_AOL_DEBUG),y)
    #        subdir-ccflags-y += -Werror -I$(srctree)/drivers/misc/mediatek/connectivity/aoltest/
    #    endif
    #endif

    # Do Nothing, move to standalone repo
    MODULE_NAME := connadp
    obj-$(CONFIG_MTK_COMBO) += $(MODULE_NAME).o

    $(MODULE_NAME)-objs += common/connectivity_build_in_adapter.o
    $(MODULE_NAME)-objs += common/wmt_build_in_adapter.o
    $(MODULE_NAME)-objs += power_throttling/adapter.o
    $(MODULE_NAME)-objs += power_throttling/core.o
    ifeq ($(CONFIG_CONN_PWR_DEBUG),y)
        $(MODULE_NAME)-objs += power_throttling/test.o
    endif

    #ifneq ($(CONFIG_MTK_TINYSYS_SCP_SUPPORT),)
        ###########################################################################
        # SCP
    #    $(MODULE_NAME)-objs += conap_scp/msg_thread.o
    #    $(MODULE_NAME)-objs += conap_scp/ring_buffer.o
    #    $(MODULE_NAME)-objs += conap_scp/conap_scp_core.o
    #    $(MODULE_NAME)-objs += conap_scp/conap_scp_ipi.o
    #    $(MODULE_NAME)-objs += conap_scp/conap_platform_data.o
        #$(MODULE_NAME)-objs += conap_scp/conap_scp_test.o
        ###########################################################################
        # Aoltest
    #    ifeq ($(CONFIG_MTK_AOL_DEBUG),y)
    #        ccflags-y += -D AOLTEST_SUPPORT
    #        $(MODULE_NAME)-objs += aoltest/aoltest_core.o
    #        $(MODULE_NAME)-objs += aoltest/aoltest_netlink.o
    #        $(MODULE_NAME)-objs += aoltest/aoltest_ring_buffer.o
    #    endif
    #endif

    ifeq ($(CONFIG_MTK_COMBO), y)
        ccflags-y += -D CFG_CONNADP_BUILD_IN
    endif
    # Do build-in for Makefile checking
    # export CONFIG_WLAN_DRV_BUILD_IN=y

    ifeq ($(CONFIG_WLAN_DRV_BUILD_IN),y)
        PATH_TO_WMT_DRV      = vendor/mediatek/kernel_modules/connectivity/common
        PATH_TO_WLAN_CHR_DRV = vendor/mediatek/kernel_modules/connectivity/wlan/adaptor
        PATH_TO_WLAN_DRV     = vendor/mediatek/kernel_modules/connectivity/wlan/core/gen4m

        ABS_PATH_TO_WMT_DRV      = $(srctree)/../$(PATH_TO_WMT_DRV)
        ABS_PATH_TO_WLAN_CHR_DRV = $(srctree)/../$(PATH_TO_WLAN_CHR_DRV)
        ABS_PATH_TO_WLAN_DRV     = $(srctree)/../$(PATH_TO_WLAN_DRV)

        # check wlan driver folder
        ifeq (,$(wildcard $(ABS_PATH_TO_WMT_DRV)))
            $(error $(ABS_PATH_TO_WMT_DRV) is not existed)
        endif
        ifeq (,$(wildcard $(ABS_PATH_TO_WLAN_CHR_DRV)))
            $(error $(ABS_PATH_TO_WLAN_CHR_DRV) is not existed)
        endif
        ifeq (,$(wildcard $(ABS_PATH_TO_WLAN_DRV)))
            $(error $(ABS_PATH_TO_WLAN_DRV) is not existed)
        endif

        $(warning symbolic link to $(PATH_TO_WMT_DRV))
        $(warning symbolic link to $(PATH_TO_WLAN_CHR_DRV))
        $(warning symbolic link to $(PATH_TO_WLAN_DRV))

        $(shell unlink $(srctree)/$(src)/wmt_drv)
        $(shell unlink $(srctree)/$(src)/wmt_chrdev_wifi)
        $(shell unlink $(srctree)/$(src)/wlan_drv_gen4m)

        $(shell ln -s $(ABS_PATH_TO_WMT_DRV)      $(srctree)/$(src)/wmt_drv)
        $(shell ln -s $(ABS_PATH_TO_WLAN_CHR_DRV) $(srctree)/$(src)/wmt_chrdev_wifi)
        $(shell ln -s $(ABS_PATH_TO_WLAN_DRV)     $(srctree)/$(src)/wlan_drv_gen4m)

        # for gen4m options
        export CONFIG_MTK_COMBO_WIFI_HIF=axi
        export MTK_COMBO_CHIP=CONNAC
        export WLAN_CHIP_ID=6765
        export MTK_ANDROID_WMT=y

        # Do build-in for xxx.c checking
        subdir-ccflags-y += -D MTK_WCN_REMOVE_KERNEL_MODULE
        subdir-ccflags-y += -D MTK_WCN_BUILT_IN_DRIVER
        obj-y += wmt_drv/
        obj-y += wmt_chrdev_wifi/
        obj-y += wlan_drv_gen4m/
    endif

    # Cooking missing MTK Modules @ ravindu644
    # WMT driver (Common dependency)
    PATH_TO_WMT_DRV := vendor/mediatek/kernel_modules/connectivity/common
    $(shell ln -s -f $(TOP)/$(PATH_TO_WMT_DRV) $(srctree)/$(src)/wmt_drv_ext)

    obj-m += wmt_drv_ext/

    # --- Mediatek Bluetooth Driver ---
    ifeq ($(CONFIG_MTK_BT_DRV_EXTERNAL),y)

        PATH_TO_BT_DRV := vendor/mediatek/kernel_modules/connectivity/bt

        $(warning Building external BT module from $(PATH_TO_BT_DRV))
        $(shell ln -s -f $(TOP)/$(PATH_TO_BT_DRV) $(srctree)/$(src)/bt_drv_ext)

        subdir-ccflags-y += -I$(TOP)/$(PATH_TO_BT_DRV)/linux_v2/include
        subdir-ccflags-y += -I$(TOP)/$(PATH_TO_BT_DRV)/mt66xx/include/btif

        export BT_PLATFORM=connac1x
        export MTK_PLATFORM=mt6789

        obj-m += bt_drv_ext/mt66xx/wmt/
    endif

    # --- Mediatek WLAN Driver ---
    ifeq ($(CONFIG_WLAN_DRV_MODULE),y)

        PATH_TO_WLAN_CHR_DRV := vendor/mediatek/kernel_modules/connectivity/wlan/adaptor
        PATH_TO_WLAN_DRV := vendor/mediatek/kernel_modules/connectivity/wlan/core/gen4m

        WLAN_HIF_TYPE := axi

        $(warning Building WLAN driver modules)
        $(shell ln -s -f $(TOP)/$(PATH_TO_WLAN_CHR_DRV) $(srctree)/$(src)/wmt_chrdev_wifi_ext)
        $(shell ln -s -f $(TOP)/$(PATH_TO_WLAN_DRV) $(srctree)/$(src)/wlan_drv_gen4m_ext)

        # Essential WLAN include paths
        subdir-ccflags-y += -I$(TOP)/$(PATH_TO_WLAN_DRV)/os/linux/include
        subdir-ccflags-y += -I$(TOP)/$(PATH_TO_WLAN_DRV)/os/none/include
        subdir-ccflags-y += -I$(TOP)/$(PATH_TO_WLAN_DRV)/os
        subdir-ccflags-y += -I$(TOP)/$(PATH_TO_WLAN_DRV)/os/linux/hif/$(WLAN_HIF_TYPE)/include
        subdir-ccflags-y += -I$(TOP)/$(PATH_TO_WLAN_DRV)/os/linux/hif/common/include
        subdir-ccflags-y += -I$(TOP)/$(PATH_TO_WLAN_DRV)/wlan_service/include
        subdir-ccflags-y += -I$(TOP)/$(PATH_TO_WLAN_DRV)/include
        subdir-ccflags-y += -I$(TOP)/$(PATH_TO_WLAN_DRV)/include/nic
        subdir-ccflags-y += -I$(TOP)/$(PATH_TO_WLAN_DRV)/include/mgmt
        subdir-ccflags-y += -I$(TOP)/$(PATH_TO_WLAN_DRV)/include/chips
        subdir-ccflags-y += -I$(TOP)/$(PATH_TO_WLAN_DRV)/include/wpa_supp
        subdir-ccflags-y += -I$(TOP)/$(PATH_TO_WLAN_DRV)/wlan_service/service/include
        subdir-ccflags-y += -I$(TOP)/$(PATH_TO_WLAN_DRV)/wlan_service/glue/osal/include
        subdir-ccflags-y += -I$(TOP)/$(PATH_TO_WLAN_DRV)/wlan_service/glue/hal/include
        subdir-ccflags-y += -I$(TOP)/vendor/mediatek/kernel_modules/connectivity/wlan/core/gen4m_ext/include
        subdir-ccflags-y += -I$(TOP)/vendor/mediatek/kernel_modules/connectivity/wlan/core/gen4m_ext/include/mgmt
        subdir-ccflags-y += -Wno-unused-variable -Wno-unused-but-set-variable

        # Build wmt_chrdev_wifi.ko by pointing to the correct subdirectory
        # and exporting the variables its internal Kbuild needs.
        export CONNAC_VER=1_0

        obj-m += wmt_chrdev_wifi_ext/build/connac1x/

        # Build wlan_drv_gen4m_6835.ko
        export CONFIG_MTK_COMBO_WIFI_HIF=axi
        export MTK_COMBO_CHIP=SOC2_1X1
        export WLAN_CHIP_ID=6835
        export MTK_ANDROID_WMT=y
        export MODULE_NAME=wlan_drv_gen4m_6835

        obj-m += wlan_drv_gen4m_ext/
    endif

# Otherwise we were called directly from the command line;
# invoke the kernel build system.
else
    KERNELDIR ?= /lib/modules/$(shell uname -r)/build
    PWD  := $(shell pwd)
default:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules
endif
