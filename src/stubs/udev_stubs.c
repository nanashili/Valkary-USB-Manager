// Stub implementations for udev functions when cross-compiling
// These provide dummy implementations to satisfy the linker
// The actual udev library will be linked at runtime on the target system

#include <stddef.h>

// Opaque types
typedef struct udev udev;
typedef struct udev_monitor udev_monitor;
typedef struct udev_device udev_device;

// Stub implementations
udev* udev_new(void) {
    return NULL;
}

void udev_unref(udev* udev) {
    (void)udev;
}

udev_monitor* udev_monitor_new_from_netlink(udev* udev, const char* name) {
    (void)udev;
    (void)name;
    return NULL;
}

int udev_monitor_filter_add_match_subsystem_devtype(udev_monitor* udev_monitor, const char* subsystem, const char* devtype) {
    (void)udev_monitor;
    (void)subsystem;
    (void)devtype;
    return -1;
}

int udev_monitor_enable_receiving(udev_monitor* udev_monitor) {
    (void)udev_monitor;
    return -1;
}

int udev_monitor_get_fd(udev_monitor* udev_monitor) {
    (void)udev_monitor;
    return -1;
}

void udev_monitor_unref(udev_monitor* udev_monitor) {
    (void)udev_monitor;
}

udev_device* udev_monitor_receive_device(udev_monitor* udev_monitor) {
    (void)udev_monitor;
    return NULL;
}

const char* udev_device_get_action(udev_device* udev_device) {
    (void)udev_device;
    return NULL;
}

const char* udev_device_get_devnode(udev_device* udev_device) {
    (void)udev_device;
    return NULL;
}

const char* udev_device_get_sysattr_value(udev_device* udev_device, const char* sysattr) {
    (void)udev_device;
    (void)sysattr;
    return NULL;
}

void udev_device_unref(udev_device* udev_device) {
    (void)udev_device;
}