#Android makefile to build kernel as a part of Android Build
PERL		= perl

KERNEL_TARGET := $(strip $(INSTALLED_KERNEL_TARGET))
ifeq ($(KERNEL_TARGET),)
INSTALLED_KERNEL_TARGET := $(PRODUCT_OUT)/kernel
endif

TARGET_KERNEL_MAKE_ENV := $(strip $(TARGET_KERNEL_MAKE_ENV))
ifeq ($(TARGET_KERNEL_MAKE_ENV),)
KERNEL_MAKE_ENV :=
else
KERNEL_MAKE_ENV := $(TARGET_KERNEL_MAKE_ENV)
endif

TARGET_KERNEL_ARCH := $(strip $(TARGET_KERNEL_ARCH))
ifeq ($(TARGET_KERNEL_ARCH),)
KERNEL_ARCH := arm
else
KERNEL_ARCH := $(TARGET_KERNEL_ARCH)
endif

TARGET_KERNEL_HEADER_ARCH := $(strip $(TARGET_KERNEL_HEADER_ARCH))
ifeq ($(TARGET_KERNEL_HEADER_ARCH),)
KERNEL_HEADER_ARCH := $(KERNEL_ARCH)
else
$(warning Forcing kernel header generation only for '$(TARGET_KERNEL_HEADER_ARCH)')
KERNEL_HEADER_ARCH := $(TARGET_KERNEL_HEADER_ARCH)
endif

# Force 32-bit binder IPC for 64bit kernel with 32bit userspace
ifeq ($(KERNEL_ARCH),arm64)
ifeq ($(TARGET_ARCH),arm)
KERNEL_CONFIG_OVERRIDE := CONFIG_ANDROID_BINDER_IPC_32BIT=y
endif
endif

TARGET_KERNEL_CROSS_COMPILE_PREFIX := $(strip $(TARGET_KERNEL_CROSS_COMPILE_PREFIX))
ifeq ($(TARGET_KERNEL_CROSS_COMPILE_PREFIX),)
KERNEL_CROSS_COMPILE := arm-eabi-
else
KERNEL_CROSS_COMPILE := $(shell pwd)/$(TARGET_TOOLS_PREFIX)
endif

ifeq ($(KERNEL_LLVM_SUPPORT), true)
  ifeq ($(KERNEL_SD_LLVM_SUPPORT), true)  #Using sd-llvm compiler
    ifeq ($(shell echo $(SDCLANG_PATH) | head -c 1),/)
       KERNEL_LLVM_BIN := $(SDCLANG_PATH)/clang
    else
       KERNEL_LLVM_BIN := $(shell pwd)/$(SDCLANG_PATH)/clang
    endif
    $(warning "Using sdllvm" $(KERNEL_LLVM_BIN))
  else
     KERNEL_LLVM_BIN := $(shell pwd)/$(CLANG) #Using aosp-llvm compiler
    $(warning "Using aosp-llvm" $(KERNEL_LLVM_BIN))
  endif
endif

ifeq ($(TARGET_PREBUILT_KERNEL),)

KERNEL_GCC_NOANDROID_CHK := $(shell (echo "int main() {return 0;}" | $(KERNEL_CROSS_COMPILE)gcc -E -mno-android - > /dev/null 2>&1 ; echo $$?))

real_cc :=
ifeq ($(KERNEL_LLVM_SUPPORT),true)
real_cc := REAL_CC=$(KERNEL_LLVM_BIN) CLANG_TRIPLE=aarch64-linux-gnu-
else
ifeq ($(strip $(KERNEL_GCC_NOANDROID_CHK)),0)
KERNEL_CFLAGS := KCFLAGS=-mno-android
endif
endif

mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
current_dir := $(notdir $(patsubst %/,%,$(dir $(mkfile_path))))
ifeq ($(TARGET_KERNEL_VERSION),)
    TARGET_KERNEL_VERSION := 3.18
endif
TARGET_KERNEL := msm-$(TARGET_KERNEL_VERSION)
ifeq ($(TARGET_KERNEL),$(current_dir))
    # New style, kernel/msm-version
    BUILD_ROOT_LOC := ../../
    TARGET_KERNEL_SOURCE := kernel/$(TARGET_KERNEL)
    KERNEL_OUT := $(TARGET_OUT_INTERMEDIATES)/kernel/$(TARGET_KERNEL)
    KERNEL_SYMLINK := $(TARGET_OUT_INTERMEDIATES)/KERNEL_OBJ
    KERNEL_USR := $(KERNEL_SYMLINK)/usr
else
    # Legacy style, kernel source directly under kernel
    KERNEL_LEGACY_DIR := true
    BUILD_ROOT_LOC := ../
    TARGET_KERNEL_SOURCE := kernel
    KERNEL_OUT := $(TARGET_OUT_INTERMEDIATES)/KERNEL_OBJ
endif

KERNEL_CONFIG := $(KERNEL_OUT)/.config

ifeq ($(KERNEL_DEFCONFIG)$(wildcard $(KERNEL_CONFIG)),)
$(error Kernel configuration not defined, cannot build kernel)
else

ifeq ($(TARGET_USES_UNCOMPRESSED_KERNEL),true)
$(info Using uncompressed kernel)
TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/Image
else
ifeq ($(KERNEL_ARCH),arm64)
TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/Image.gz
else
TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/zImage
endif
endif

ifneq ($(DTC_EXT),)
KERNEL_MAKE_DTC_EXT := DTC_EXT=$(DTC_EXT)
#Define dependency on dtc module
KERNEL_DTC_EXT := dtc
else
KERNEL_MAKE_DTC_EXT :=
endif

ifeq ($(TARGET_KERNEL_APPEND_DTB), true)
$(info Using appended DTB)
TARGET_PREBUILT_INT_KERNEL := $(TARGET_PREBUILT_INT_KERNEL)-dtb
else
$(info Using DTB Image)
INSTALLED_DTBIMAGE_TARGET := $(PRODUCT_OUT)/dtb.img
endif

# Creating a dtb.img once the kernel is compiled if TARGET_KERNEL_APPEND_DTB is set to be false
$(INSTALLED_DTBIMAGE_TARGET): $(INSTALLED_KERNEL_TARGET)
	cat $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/dts/qcom/*.dtb > $@

KERNEL_HEADERS_INSTALL := $(KERNEL_OUT)/usr
KERNEL_MODULES_INSTALL ?= system
KERNEL_MODULES_OUT ?= $(PRODUCT_OUT)/$(KERNEL_MODULES_INSTALL)/lib/modules
# relative path from KERNEL_OUT to kernel source directory
KERNEL_SOURCE_RELATIVE_PATH := ../../../../../../kernel

TARGET_PREBUILT_KERNEL := $(TARGET_PREBUILT_INT_KERNEL)

define mv-modules
mdpath=`find $(KERNEL_MODULES_OUT) -type f -name modules.order`;\
if [ "$$mdpath" != "" ];then\
mpath=`dirname $$mdpath`;\
ko=`find $$mpath/kernel -type f -name *.ko`;\
for i in $$ko; do mv $$i $(KERNEL_MODULES_OUT)/; done;\
fi
endef

define clean-module-folder
mdpath=`find $(KERNEL_MODULES_OUT) -type f -name modules.order`;\
if [ "$$mdpath" != "" ];then\
mpath=`dirname $$mdpath`; rm -rf $$mpath;\
fi
endef

ifneq ($(KERNEL_LEGACY_DIR),true)
$(KERNEL_USR): $(KERNEL_HEADERS_INSTALL)
	rm -rf $(KERNEL_SYMLINK)
	ln -s kernel/$(TARGET_KERNEL) $(KERNEL_SYMLINK)

$(TARGET_PREBUILT_INT_KERNEL): $(KERNEL_USR)
endif

include kernel/defconfig.mk

KERNEL_HEADER_DEFCONFIG := $(strip $(KERNEL_HEADER_DEFCONFIG))
ifeq ($(KERNEL_HEADER_DEFCONFIG),)
KERNEL_HEADER_DEFCONFIG := $(TARGET_DEFCONFIG)
endif

define do-kernel-config
	( cp $(3) $(2) && $(7) -C $(4) O=$(1) $(KERNEL_MAKE_ENV) ARCH=$(5) CROSS_COMPILE=$(6) KBUILD_BUILD_USER=$(TARGET_KERNEL_BUILD_USER) KBUILD_BUILD_HOST=$(TARGET_KERNEL_BUILD_HOST) defoldconfig ) || ( rm -f $(2) && false )
endef

$(KERNEL_OUT):
	mkdir -p $(KERNEL_OUT)

$(KERNEL_CONFIG): $(KERNEL_OUT) $(TARGET_DEFCONFIG)
	$(call do-kernel-config,$(BUILD_ROOT_LOC)$(KERNEL_OUT),$@,$(TARGET_DEFCONFIG),$(TARGET_KERNEL_SOURCE),$(KERNEL_ARCH),$(KERNEL_CROSS_COMPILE),$(real_cc),$(MAKE))
	$(hide) if [ ! -z "$(KERNEL_CONFIG_OVERRIDE)" ]; then \
			echo "Overriding kernel config with '$(KERNEL_CONFIG_OVERRIDE)'"; \
			echo $(KERNEL_CONFIG_OVERRIDE) >> $(KERNEL_OUT)/.config; \
			$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) oldconfig; fi

$(TARGET_PREBUILT_INT_KERNEL): $(KERNEL_OUT) $(KERNEL_CONFIG) $(KERNEL_HEADERS_INSTALL) $(KERNEL_DTC_EXT)
	$(hide) echo "Building kernel..."
	$(hide) rm -rf $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/dts
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) KBUILD_RELSRC=$(KERNEL_SOURCE_RELATIVE_PATH) O=$(BUILD_ROOT_LOC)/$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) KBUILD_BUILD_USER=$(TARGET_KERNEL_BUILD_USER) KBUILD_BUILD_HOST=$(TARGET_KERNEL_BUILD_HOST) $(KERNEL_MAKE_DTC_EXT) $(KERNEL_CFLAGS)
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) KBUILD_RELSRC=$(KERNEL_SOURCE_RELATIVE_PATH) O=$(BUILD_ROOT_LOC)/$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) KBUILD_BUILD_USER=$(TARGET_KERNEL_BUILD_USER) KBUILD_BUILD_HOST=$(TARGET_KERNEL_BUILD_HOST) $(KERNEL_MAKE_DTC_EXT) $(KERNEL_CFLAGS) dtbs
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) KBUILD_RELSRC=$(KERNEL_SOURCE_RELATIVE_PATH) O=$(BUILD_ROOT_LOC)/$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) KBUILD_BUILD_USER=$(TARGET_KERNEL_BUILD_USER) KBUILD_BUILD_HOST=$(TARGET_KERNEL_BUILD_HOST) $(KERNEL_MAKE_DTC_EXT) $(KERNEL_CFLAGS) modules
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) KBUILD_RELSRC=$(KERNEL_SOURCE_RELATIVE_PATH) O=$(BUILD_ROOT_LOC)/$(KERNEL_OUT) INSTALL_MOD_PATH=$(BUILD_ROOT_LOC)../$(KERNEL_MODULES_INSTALL) INSTALL_MOD_STRIP="--strip-debug --remove-section=.note.gnu.build-id" $(KERNEL_MAKE_ENV) $(KERNEL_MAKE_DTC_EXT) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) KBUILD_BUILD_USER=$(TARGET_KERNEL_BUILD_USER) KBUILD_BUILD_HOST=$(TARGET_KERNEL_BUILD_HOST) modules_install
	$(mv-modules)
	$(clean-module-folder)

$(KERNEL_HEADERS_INSTALL): $(KERNEL_OUT) $(KERNEL_CONFIG)
	$(hide) if [ ! -z "$(KERNEL_HEADER_DEFCONFIG)" ]; then \
			rm -f ../$(KERNEL_CONFIG); \
			$(call do-kernel-config,$(BUILD_ROOT_LOC)/$(KERNEL_OUT),$(KERNEL_CONFIG),$(KERNEL_HEADER_DEFCONFIG),kernel,$(KERNEL_HEADER_ARCH),$(KERNEL_CROSS_COMPILE),$(real_cc),$(MAKE)); \
			$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)/$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_HEADER_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) KBUILD_BUILD_USER=$(TARGET_KERNEL_BUILD_USER) KBUILD_BUILD_HOST=$(TARGET_KERNEL_BUILD_HOST) headers_install; fi
	$(hide) if [ "$(KERNEL_HEADER_DEFCONFIG)" != "$(KERNEL_DEFCONFIG)" ]; then \
			echo "Used a different defconfig for header generation"; \
			rm -f $(BUILD_ROOT_LOC)$(KERNEL_CONFIG); \
			$(call do-kernel-config,$(BUILD_ROOT_LOC)$(KERNEL_OUT),$(KERNEL_CONFIG),$(TARGET_DEFCONFIG),$(TARGET_KERNEL_SOURCE),$(KERNEL_ARCH),$(KERNEL_CROSS_COMPILE),$(real_cc),$(MAKE)); fi
	$(hide) if [ ! -z "$(KERNEL_CONFIG_OVERRIDE)" ]; then \
			echo "Overriding kernel config with '$(KERNEL_CONFIG_OVERRIDE)'"; \
			echo $(KERNEL_CONFIG_OVERRIDE) >> $(KERNEL_OUT)/.config; \
			$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) oldconfig; fi

.PHONY: kerneltags
kerneltags: $(KERNEL_OUT) $(KERNEL_CONFIG)
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)/$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) KBUILD_BUILD_USER=$(TARGET_KERNEL_BUILD_USER) KBUILD_BUILD_HOST=$(TARGET_KERNEL_BUILD_HOST) tags

.PHONY: kernelconfig
kernelconfig: $(KERNEL_OUT) $(KERNEL_CONFIG)
	env KCONFIG_NOTIMESTAMP=true \
	     $(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)/$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) KBUILD_BUILD_USER=$(TARGET_KERNEL_BUILD_USER) KBUILD_BUILD_HOST=$(TARGET_KERNEL_BUILD_HOST) menuconfig
	env KCONFIG_NOTIMESTAMP=true \
	     $(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)/$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) KBUILD_BUILD_USER=$(TARGET_KERNEL_BUILD_USER) KBUILD_BUILD_HOST=$(TARGET_KERNEL_BUILD_HOST) savedefconfig
	cp $(KERNEL_OUT)/defconfig $(TARGET_KERNEL_SOURCE)/arch/$(KERNEL_ARCH)/configs/$(KERNEL_DEFCONFIG)

endif
endif
