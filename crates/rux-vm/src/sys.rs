use mach2::boolean::boolean_t;
use mach2::kern_return::kern_return_t;
use mach2::message::mach_msg_type_number_t;
use mach2::port::mach_port_t;
use mach2::vm_prot::vm_prot_t;
use mach2::vm_types::{mach_vm_address_t, mach_vm_size_t, vm_offset_t};
pub const MACH_FALSE: boolean_t = 0;
pub const MACH_TRUE: boolean_t = 1;

pub const VM_FLAGS_ANYWHERE: libc::c_int = 1;

pub const VM_PROT_NONE: vm_prot_t = 0x00;
pub const VM_PROT_READ: vm_prot_t = 0x01;
pub const VM_PROT_WRITE: vm_prot_t = 0x02;
pub const VM_PROT_EXECUTE: vm_prot_t = 0x04;
pub const VM_PROT_DEFAULT: vm_prot_t = VM_PROT_READ | VM_PROT_WRITE;
pub const VM_PROT_ALL: vm_prot_t = VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE;

unsafe extern "C" {
    pub fn mach_task_self() -> mach_port_t;

    pub fn task_for_pid(
        target_tport: mach_port_t,
        pid: libc::c_int,
        t: *mut mach_port_t,
    ) -> kern_return_t;

    pub fn mach_port_deallocate(task: mach_port_t, name: mach_port_t) -> kern_return_t;

    pub fn mach_vm_allocate(
        target: mach_port_t,
        address: *mut mach_vm_address_t,
        size: mach_vm_size_t,
        flags: libc::c_int,
    ) -> kern_return_t;

    pub fn mach_vm_deallocate(
        target: mach_port_t,
        address: mach_vm_address_t,
        size: mach_vm_size_t,
    ) -> kern_return_t;

    pub fn mach_vm_write(
        target_task: mach_port_t,
        address: mach_vm_address_t,
        data: vm_offset_t,
        data_cnt: mach_msg_type_number_t,
    ) -> kern_return_t;

    pub fn mach_vm_read_overwrite(
        target_task: mach_port_t,
        address: mach_vm_address_t,
        size: mach_vm_size_t,
        data: mach_vm_address_t,
        outsize: *mut mach_vm_size_t,
    ) -> kern_return_t;

    pub fn mach_vm_protect(
        target_task: mach_port_t,
        address: mach_vm_address_t,
        size: mach_vm_size_t,
        set_maximum: boolean_t,
        new_protection: vm_prot_t,
    ) -> kern_return_t;

    pub fn vm_protect(
        target_task: mach_port_t,
        address: mach_vm_address_t,
        size: mach_vm_size_t,
        set_maximum: boolean_t,
        new_protection: vm_prot_t,
    ) -> kern_return_t;

    pub fn thread_create_running(
        parent_task: mach_port_t,
        flavor: libc::c_int,
        new_state: *const libc::c_void,
        new_state_count: mach_msg_type_number_t,
        child_act: *mut mach_port_t,
    ) -> kern_return_t;

    pub fn thread_terminate(target_act: mach_port_t) -> kern_return_t;
}
