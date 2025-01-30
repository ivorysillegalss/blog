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

运行效果和测试脚本有：

```sh
$ pgtbltest
ugetpid_test starting
ugetpid_test: OK
```
```
chenz@Chenzc:~/lab$ sudo python3 grade-lab-pgtbl ugetpid
make: 'kernel/kernel' is up to date.
== Test pgtbltest == (3.1s)
== Test   pgtbltest: ugetpid ==
  pgtbltest: ugetpid: OK
```



### Print a page table

该命令是要在xv6启动的时候 打印`init`进程涉及到的pte和物理地址

在理解了内存管理的结构（多级页表）之后就很简单了 在递归寻找下一级页表与地址的时候`print`即可

可根据hints理解一下`kernel/vm.c`中的`freewalk()`函数中的逻辑

eg:

```c
// Recursively free page-table pages.
// All leaf mappings must already have been removed.
// 递归到最深层 解索引.
void freewalk(pagetable_t pagetable) {
    // there are 2^9 = 512 PTEs in a page table.
    for (int i = 0; i < 512; i++) {
        pte_t pte = pagetable[i];
        // pte不存在 或PTE_V没有设置

        // 标识非叶子节点（页目录项） 中间节点是没有R W X这些权限的
        if ((pte & PTE_V) && (pte & (PTE_R | PTE_W | PTE_X)) == 0) {
            // this PTE points to a lower-level page table.
            uint64 child = PTE2PA(pte);
            freewalk((pagetable_t)child);
            // 清除其中内容
            pagetable[i] = 0;

            // 标识为叶子节点 只有物理的节点可以有R W X这些权限
        } else if (pte & PTE_V) {
            panic("freewalk: leaf");
        }
    }
    kfree((void*)pagetable);
}
```

`freewalk()`函数的作用是在函数使用之后回收空间

于是就可以照葫芦画瓢的参照该遍历方式 在每一层页表的中间都打印其所对应的`pte`和`pa`

然后在`exec()`中 注册一个分支语句就可以

`kernel/exec.c exec()`

```c
int exec(char* path, char** argv) {
    // 打印第一个进程的页表 1为初始深度
    if (p->pid == 1) {
        printf("page table %p\n", p->pagetable);
        vmprint(p->pagetable, 1);
    }
	return argc;
}
```

`kernel/vm.c` 创建一个递归遍历函数`vmprint()`

```c
void vmprint(pagetable_t pagetable, uint depth) {
    for (int i = 0; i < 512; i++) {
        pte_t pte = pagetable[i];

        // 同理 非叶子节点 无权限
        if ((pte & PTE_V) && (pte & (PTE_R | PTE_W | PTE_X)) == 0) {

            // 获取目录项的内存
            uint64 child = PTE2PA(pte);

            // 遍历表示深度
            for (int j = 1; j < depth; j++) {
                printf(".. ");
            }
            printf("..");
            printf("%d: pte %p pa %p\n", i, (void*)pte, (void*)child);

            // 递归查找
            vmprint((pagetable_t)child, depth + 1);

            // 叶子节点
        } else if (pte & PTE_V) {
            printf(".. .. ..");
            printf("%d: pte %p pa %p\n", i, (void*)pte, (void*)PTE2PA(pte));
        }
    }
}
```

最后效果和测试程序有：

```c
xv6 kernel is booting

hart 2 starting
hart 1 starting
page table 0x0000000087f6e000
..0: pte 0x0000000021fda801 pa 0x0000000087f6a000
.. ..0: pte 0x0000000021fda401 pa 0x0000000087f69000
.. .. ..0: pte 0x0000000021fdac1f pa 0x0000000087f6b000
.. .. ..1: pte 0x0000000021fda00f pa 0x0000000087f68000
.. .. ..2: pte 0x0000000021fd9c1f pa 0x0000000087f67000
..255: pte 0x0000000021fdb401 pa 0x0000000087f6d000
.. ..511: pte 0x0000000021fdb001 pa 0x0000000087f6c000
.. .. ..509: pte 0x0000000021fddc13 pa 0x0000000087f77000
.. .. ..510: pte 0x0000000021fdd807 pa 0x0000000087f76000
.. .. ..511: pte 0x0000000020001c0b pa 0x0000000080007000
init: starting sh
```

```bash
chenz@Chenzc:~/lab$ sudo python3 grade-lab-pgtbl printout
[sudo] password for chenz:
make: 'kernel/kernel' is up to date.
== Test pte printout == pte printout: OK (2.9s)
```



### Detecting which pages have been accessed

该部分本质上就是提供某些页面是否有被使用的信息 通过`PTE_A` 判断自上次调用该方法之后 此页面是否有被访问过

而在RISC-V中 往往硬件会为`PTE_A`设为1

> **在硬件层面上**，`PTE_A` 是由硬件自动管理的标志位，当页面被访问时（无论是读取、写入还是执行），硬件会自动将 `PTE_A` 设置为 1。这个过程是完全由硬件（特别是内存管理单元MMU）在进行地址转换和页面访问时自动执行的，操作系统并不需要手动干预。

通过hints可以在RISC-V手册中找到它所对应的宏可以设置为

```c
#define PTE_A (1L << 6)  // accessed 访问位
```

所以在调用到的时候 只需要清除该位中的值即可

而获取这些有关的信息 需要将得到的va翻译为pte对象

所以我这里是再次包装了一个方法 也可以直接把`walk()`函数暴露出来

`kernel/vm.c walkaddr()`

```c
pte_t* walkpte(pagetable_t pagetable, uint64 va) {
    return walk(pagetable, va, 0);
}
```

题目提供的调用方法骨架中 形参分别为 **起始地址，页数量，结果存储指针**

结合上方的思路 我们只需要配合`walkaddr()`函数 将对应对象的pte获取出来

再判断对应的`PTE_A` 是否为所求

合法的话加入结果掩码中即可

最后通过`copyout()`将内核空间中的数据复制一份 以指针形式传递给用户空间.

具体实现有：

`kernel/proc.c & kernel/sysproc.c`这里分开了两个文件写 实际上分开合起来都没差

```c
# sysproc.c
uint64 sys_pgaccess(void) {
    uint64 start_address;
    int pages_num;
    uint64 bitmask_addr;
    if (argaddr(0, &start_address) | argint(1, &pages_num) |
        argaddr(2, &bitmask_addr)) {
        return -1;
    }
    // 人为设置访问页上限 没有啥原因 PGSIZE好看而已
    if (pages_num > PGSIZE) {
        return -1;
    }
    return isaccessed(start_address, pages_num, bitmask_addr);
}

# proc.c
int ceildivide(int a, int b) {
    if (a % b == 0) {
        return a / b;
    }
    return a / b + 1;
}

int isaccessed(uint64 start_address, int page_nums, uint64 bit_mask) {
    struct proc* p = myproc();

    uint8 bitmask[ceildivide(page_nums, 8)];
    memset(bitmask, 0, sizeof(bitmask));

    for (int i = 0; i < page_nums; i++) {
        uint64 addr = start_address + i * PGSIZE;
        if (addr > MAXVA)
            return -1;

        pte_t* pte = walkpte(p->pagetable, addr);
        if (pte && (*pte & PTE_V) && (*pte & PTE_A)) {
            bitmask[i / 8] |= (1 << (i % 8));
            *pte &= ~PTE_A;
        }
    }
    if (copyout(p->pagetable, bit_mask, (char*)&bitmask, sizeof(bitmask)) < 0) {
        return -1;
    }
    return 0;
}
```

当然了 需要在`defs.h`中注册`isaccessed()`

以上完事

程序运行和脚本测试结果有:

```sh
$ pgtbltest
ugetpid_test starting
ugetpid_test: OK
pgaccess_test starting
pgaccess_test: OK
pgtbltest: all tests succeeded
```

```sh
chenz@Chenzc:~/lab$ sudo python3 grade-lab-pgtbl pgaccess
make: 'kernel/kernel' is up to date.
== Test pgtbltest == (4.4s)
== Test   pgtbltest: pgaccess ==
  pgtbltest: pgaccess: OK
```

