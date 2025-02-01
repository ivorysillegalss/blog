---
title: mit6.s081-lecture6
date: 2025-01-31 20:27:11
tags: mit6.s081
---

6和7中是陷入的代码相关的问题和页表的复盘 很多涉及的内容已经在前面的文章中描述过 这里不赘述

# Lecture6

### Trap机制

trap机制是指用户从用户空间切换到内核空间的渠道方法 而触发它的情况包括：

- 执行系统调用
- 出现除零错误 等异常 需要进行handle
- 设备主动触发中断 可能是在需要IO设备交互等的前提下触发



### 从用户空间陷入

以系统调用为例，从顶层开始描述有：

eg：

- 在`user/sleep.c`中调用了用户侧的`sleep()`方法

- 该方法是通过`usys.pl`文件生成的`usys.S`汇编脚本文件 提供了一个调用的汇编接口

```asm
.global sleep
sleep:
 li a7, SYS_sleep
 ecall
 ret
```

上方就是用户侧`sleep()`方法的实际代码 这里调用了一个`ecall`指令

该指令准备好一切进入内核空间的环境：

设置当前为`supervisor mode`

存原程序计数器`PC`值到`sepc`寄存器当中

将程序计数器设置为控制寄存器`stvec`寄存器当中

同时设置`scause`寄存器中的值 该寄存器存储中断原因 这里存储的值是`8` 代表环境调用

这个`stvec`就是陷阱的地址 `ecall`在执行玩前置操作之后 跳转到的地址 在这里是`trampoline.S`的头部

*大白话就是说 设置好一些标志位之后 跳转到陷入代码块处*

然后可以观察...

```asm
        # swap a0 and sscratch
        # so that a0 is TRAPFRAME
        csrrw a0, sscratch, a0

        # save the user registers in TRAPFRAME
        sd ra, 40(a0)
        sd sp, 48(a0)
        ...
```

这里先将对应的数据从暂存寄存器`sscratch`中拿出来

然后将它与`a0`对换

将这个数据存储到`TRAPFRAME`当中

在全部安置完之后 准备一些前往内核空间所必须的标识值 加载为内核页表的satp值等等等等

```asm
        # restore kernel stack pointer from p->trapframe->kernel_sp
        ld sp, 8(a0)
        
        # make tp hold the current hartid, from p->trapframe->kernel_hartid
        ld tp, 32(a0)

        # load the address of usertrap(), p->trapframe->kernel_trap
        # 在当前进程的trapframe中已经规定了地址 此处只需要在内核空间中读取即可 读取执行的起始地址 跳转过去执行逻辑
        ld t0, 16(a0)
        
        # restore kernel page table from p->trapframe->kernel_satp
        ld t1, 0(a0)
        csrw satp, t1
        sfence.vma zero, zero
```

然后就跳转到内核空间中陷入的方法

```asm
        # jump to usertrap(), which does not return
        jr t0
```



- 这一块代码是在`kernel/trap.c`当中

同样需要进行一些前后置校验

```c
    // 判断状态是否合法 （当前权限模式）
    if ((r_sstatus() & SSTATUS_SPP) != 0)
        panic("usertrap: not from user mode");
        
        
    if (r_scause() == 8) {
        // system call

        if (p->killed)
            exit(-1);

    } else if ((which_dev = devintr()) != 0) {
        // ok
    } else {

    }
    
    if (p->killed)
        exit(-1);
        
    // 定时片花完了 主动让出CPU
    if (which_dev == 2)
        yield();
```

并且 需要保存一些以线程为颗粒度的 用户空间的值

```c
    p->trapframe->epc = r_sepc();
```

而真正执行系统调用块是在这一个分支语句当中

```c
    if (r_scause() == 8) {
        // system call

        if (p->killed)
            exit(-1);

        // sepc points to the ecall instruction,
        // but we want to return to the next instruction.
        // 此处标识成功执行 向前移动一个语句 加4
        // （4是一个指令的长度）
        p->trapframe->epc += 4;

        // an interrupt will change sstatus &c registers,
        // so don't enable until done with those registers.
        intr_on();

        // 真正执行系统调用
        syscall();
    } 
```

通过scaruse方法得知中断的原因 -> 首先观察线程是否被杀掉 -> 移动用户空间指针中语句的偏移量 -> 打开用户空间中断 -> 执行系统调用

这里会带来几个问题：

**r_scause=8是什么 怎么设置的？**

这个是在前面用户空间执行`ecall`的时候自动设置的 标识当前中断的产生原因

**+4 移动 偏移量是怎么回事？**

在RISC-V中 语句指令的长度是指定的 都是4个字节的长度

而在这个地方的`epc`寄存器当中 之前存储的是用户空间时寄存器的程序计数器 也就是`ecall`的位置

所以这里+4的目的就是为了跳过这一语句 不然回去就会重新再进行一次调用 重新执行一次之后的所有流程

**intr_on这里所谓的中断打开是怎么回事 之前的中断是关闭的吗？**

在一般的操作系统中 会由硬件保证在进入操作系统的同时就会关闭中断 这个主要是为了防止中断的嵌套

（因为如果不进行人为的关闭的话 有可能在内核中无止境的再次中断）

但是xv6中理论上是允许中断的产生的 因为从这里可以可以看到 真正执行系统调用的时候 是在允许中断之后

换句话来说 也就是 **在允许中断后 执行系统调用前** 此时有可能会产生中断的嵌套

但是这种情况下 嵌套外部的中断的逻辑状态已经设置好 **即使发生了嵌套 也能保证嵌套执行前后状态的逻辑一致性**

*感觉思想有点类似 MySQL中的两阶段提交*



- 调用中具体的逻辑不讲了 就是到`kernel/syscall.c`中 从注册表中得到对应的方法并且执行。 执行完后会回到此处，继续执行`usertrapret()`方法

可以看到在这个方法中也是第一时间关闭了中断 然后修改了`stvec`寄存器 其中仍然是存储`trampoline.S`中的代码段 跳转到其具体的位置 然后开始执行`ld`等 从寄存器中读取值 返回给用户空间

切换标志位 页表 sepc(用户空间中执行的进度)等

```c
    // set S Previous Privilege mode to User.
    unsigned long x = r_sstatus();
    x &= ~SSTATUS_SPP;  // clear SPP to 0 for user mode
    x |= SSTATUS_SPIE;  // enable interrupts in user mode
    w_sstatus(x);

    // set S Exception Program Counter to the saved user pc.
    w_sepc(p->trapframe->epc);

    // tell trampoline.S the user page table to switch to.
    uint64 satp = MAKE_SATP(p->pagetable);

```

找到`trampoline.S`中`userret`执行的位置


```c
    // 这里指的是 以TRAMPOLINE为基地址的 对应函数起始地址的便宜量（具体对应trampoline.S中的代码位置）
    uint64 fn = TRAMPOLINE + (userret - trampoline);
    // 将对应的指针转为函数 传入TRAPFRAME的位置和satp寄存器值进去
    ((void (*)(uint64, uint64))fn)(TRAPFRAME, satp);
```

`userret()`的asm


```asm
.globl userret
userret:
        # 此处的代码段是指系统调用完毕之后 返回用户空间时执行的代码

        # 交换寄存器中的值
        csrw satp, a1
        sfence.vma zero, zero
        
        # a0中一般来说是系统调用之后的返回值 此处将它的值转移存储到t0当中
        # 然后将sscratch寄存器和t0中的值交换
        # 根据背景可以得到 交换之前t0存储的是返回值的数据 而sscratch的作用只是暂时进行存储
        ld t0, 112(a0)
        csrw sscratch, t0
        ......
                
        # return to user mode and user pc.
        # usertrapret() set up sstatus and sepc.
        sret
```

执行完之后 `sret`命令会返回到`sepc`当中的地址 也就是**用户空间下 执行的位置** 然后从该位置继续往下执行

当然 执行的结果可以通过传进去的指针通过`copyout()`或者直接`print`等形式体现出来



### 从内核空间陷入

本质上的思路和在用户空间上是差不多的 但是由于本来就是在内核中陷入内核 

所以相比起从用户空间陷入 他就不用这么多的检查一类

但是在陷入的时候 寄存器相关的还是需要挂起保存 

详细可见`kernelvec`和`kerneltrap()`二者

