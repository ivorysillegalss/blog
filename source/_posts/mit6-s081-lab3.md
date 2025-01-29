---
title: mit6.s081 lab3
date: 2025-01-29 21:16:05
tags: mit6.s081
---

### Speed up system calls

顾名思义 该Lab就是在`user / kernel mode`之间设定一个共享只读缓存

该缓存是以线程为单位共享的 换言之 只要不影响两空间之间的数据隔离规则 就可以将其值设置在这个只读缓存当中‘

这里所设置的是pid

 内核空间和用户空间之间交互的手段是`trampoline`和`trapframe`

前者是将数据由一个态陷入另一个态的逻辑代码

后者则是在这一过程中需要携带的数据结构

在这里需要多加一个字段 类似实现`trace`的时候一样

关于这个`usyscall` 已经给出了用户侧`ugetpid()`调用实例和实际的结构体内容

`kernel/proc.c`

结构体添加元素

```c
// Per-process state
struct proc {
	...
	struct usyscall* usyscall_info;  // user / kernel model shared data
};
```

为对应的虚拟地址分配空间

```c
static struct proc* allocproc(void) {
    struct proc* p;

    for (p = proc; p < &proc[NPROC]; p++) {
        acquire(&p->lock);
        if (p->state == UNUSED) {
            goto found;
        } else {
            release(&p->lock);
        }
    }
    return 0;

found:
    p->pid = allocpid();
    p->state = USED;

    // 为内核/用户空间共享内存板块 usyscallInfo 分配内存
    if ((p->usyscall_info = (struct usyscall*)kalloc()) == 0) {
        freeproc(p);
        release(&p->lock);
        return 0;
    }
    p->usyscall_info->pid = p->pid;

    ...
    // 省略原有trapframe等逻辑
        
    return p;
}
```

绑定虚拟地址和对应的物理地址

```c
pagetable_t proc_pagetable(struct proc* p) {
    pagetable_t pagetable;
    
    ...
    
    // 这里的位置是将其放在trapframe和trampoline存储之后 所以再失败的时候 需要连之前的一同异常处理
        
    // 在虚拟内存和物理内存间 映射usyscall
    // 如果映射失败了 需要将之前成功的分配记录回滚 恢复现场
    if (mappages(pagetable, USYSCALL, PGSIZE, (uint64)(p->usyscall_info),
                 PTE_R | PTE_U) < 0) {
        uvmfree(pagetable, 0);
        // 回滚之前成功的TRAMPOLINE和TRAPFRAME间的映射
        uvmunmap(pagetable, TRAMPOLINE, 1, 0);
        uvmunmap(pagetable, TRAPFRAME, 1, 0);
        return 0;
    }

    return pagetable;
}
```

在使用之后 需要回收垃圾 回收空间 

```c
static void freeproc(struct proc* p) {
	...
    // 清除内存空间（置0）
    if (p->usyscall_info) {
        kfree((void*)p->usyscall_info);
    }
    p->usyscall_info = 0;
}
```

置0之后 需要解引用 （将物理内存空间和虚拟空间解引用）

```c
void proc_freepagetable(pagetable_t pagetable, uint64 sz) {
    uvmunmap(pagetable, TRAMPOLINE, 1, 0);
    uvmunmap(pagetable, TRAPFRAME, 1, 0);
 	// 解引用USYCALL
    uvmunmap(pagetable, USYSCALL, 1, 0);
    uvmfree(pagetable, sz);
}
```

测试脚本效果有：

```sh
$ pgtbltest
ugetpid_test starting
ugetpid_test: OK
```

