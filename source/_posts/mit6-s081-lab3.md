---
title: mit6.s081 lab3
date: 2025-01-21 14:24:54
tags: mit6.s08
---

Lab3中的主要是完成两个系统调用 分别是trace和sysinfo

### Trace

作用是查找系统调用时的锚点信息 关键点在于对整个系统调用的调用过程理解清楚



#### 系统调用在内核中的调用流

真正执行sysCall的逻辑在`kernel/syscall.c`当中。

该文件规定了**部分内核 / 用户空间复制使用到的lib方法 系统调用声明 调用宏和方法之间的map映射 真正调用时执行的syscall方法**

宏在`kernel/syscall.h`中规定

系统调用具体实现在`kernel/sysproc.c`中实现

当系统调用请求到来的时候 会通过`trampoline.S`中陷入内核

jmp至`usertrap()`方法中 该方法在`kernel/trap.c`中

在该方法就会真正调用`syscall()`方法 执行系统调用



#### 而在用户空间如何跳转到内核空间？

使用`kernel/usys.pl`文件定义 暴露向外的汇编接口

这个接口是利用了`kernel/syscall.h`下的宏定义

将映射的方法名称如`fork()`等与对应的编号`1`联系起来

在编译的时候 该文件就会编译生成汇编接口文件

外部调用`fork()`的时候 就相当于是发起了一次`ecall 1`的请求

`ecall`之后 调用了`trampoline.S`文件 之后的流程就与上面一致了



#### 系统调用注册

搞明白整个运行流程就好写了

为了注册多一个系统调用 首先需要在`syscall.h`中多一个宏定义

`syscall.h`

```c
......
#define SYS_close 21
#define SYS_trace 22
```

同时在`syscall.c`中增加新的定义

```c
static uint64 (*syscalls[])(void) = {
    [SYS_fork] sys_fork,   [SYS_exit] sys_exit,     [SYS_wait] sys_wait,
    [SYS_pipe] sys_pipe,   [SYS_read] sys_read,     [SYS_kill] sys_kill,
    [SYS_exec] sys_exec,   [SYS_fstat] sys_fstat,   [SYS_chdir] sys_chdir,
    [SYS_dup] sys_dup,     [SYS_getpid] sys_getpid, [SYS_sbrk] sys_sbrk,
    [SYS_sleep] sys_sleep, [SYS_uptime] sys_uptime, [SYS_open] sys_open,
    [SYS_write] sys_write, [SYS_mknod] sys_mknod,   [SYS_unlink] sys_unlink,
    [SYS_link] sys_link,   [SYS_mkdir] sys_mkdir,   [SYS_close] sys_close,
    [SYS_trace] sys_trace,
};
```

根据上方的运行流程 已知`syscall.c`中的宏定义对应了`sysproc.c`中的系统调用（`usys.pl`中暴露的汇编脚本联系的）

所以需要在`sysproc.c`中和`usys.pl`中都分别新增对应代码

而用户空间访问系统调用的话 是通过在`user.h`中定义的system call接口映射的 所以在`user.h`中也需要先对他声明

`user.h`

```c
......
int sleep(int);
int uptime(void);
int trace(int);
```

`sysproc.c`

```c
uint64 sys_trace(void) {
    int mask;
    if (argint(0, &mask) < 0)
        return -1;
    struct proc* p = myproc();
    // 该系统调用是追踪 只需要注册对应的系统调用编号即可
    p->trace_mask = mask;
    return 0;
}
```

`usys.pl`

```perl
......
entry("sleep");
entry("uptime");
entry("trace");
```

除此之外 Makefile啥的也肯定需要增加 不赘述



#### 实现

以上为增加系统调用所大致需要新增的流

接下来回归正题 trace系统调用本质上只是监控系统调用运行时的状态信息 

并且打印**当前pid 调用的系统调用 调用的返回值**

而用户空间`trace.c`中的代码是将`trace`和`exec`两个过程分开执行的

可得`trace`这一过程本质上是注册要打印，监控的系统调用信息

将该信息在proc结构体中新增字段并存储

`proc.h`

```c
struct proc {
    int trace_mask;               // Trace mask; if 0xFFFFFFFF all; else that plusds;
};
```

然后在`sysproc.c`中照葫芦画瓢将这个值存储进进程信息就行了 代码在上方已经给出来过

存储了这个值之后 接下来就是在程序运行的时候 做一个if判断 判断当前执行的系统调用是否需trace

为了达成这个目的 首先就是需要修改`syscall.c`中的`syscall()`， which is 真正获取编号并查表执行syscall的地方

为了打印当前syscall的名字 还需要另外建立一个索引数组 方便打印系统调用名

```c
static char* syscall_names[] = {
// syscall调用编号从1开始 这里留空是为了方便打印输出
    "",      "fork",  "exit",   "wait",   "pipe",  "read",  "kill",   "exec",
    "fstat", "chdir", "dup",    "getpid", "sbrk",  "sleep", "uptime", "open",
    "write", "mknod", "unlink", "link",   "mkdir", "close", "trace"};

void syscall(void) {
    int num;
    struct proc* p = myproc();

    // a7寄存器保存系统调用的编号 a0保存返回值与调用的函数
    num = p->trapframe->a7;
    if (num > 0 && num < NELEM(syscalls) && syscalls[num]) {
        uint64 retV = syscalls[num]();
        p->trapframe->a0 = retV;

        // 此处进行判断 并输出锚点信息
        if (p->trace_mask & (1 << num)) {
            printf("%d: syscall %s -> %d\n", p->pid, syscall_names[num], retV);
        }

    } else {
        printf("%d %s: unknown sys call %d\n", p->pid, p->name, num);
        p->trapframe->a0 = -1;
    }
}
```

然后父子进程复制时 也需要将监控信息一并复制

```c
// Create a new process, copying the parent.
// Sets up child kernel stack to return as if from fork() system call.
int fork(void) {
	...
    // 父子进程复制跟踪掩码
    np->trace_mask = p->trace_mask;
	...
}
```

就ok了 trace本身并不需要做很多操作 只需注册调用号即可

实测效果有：

```bash
$ trace 2147483647 grep hello README
3: syscall trace -> 0
3: syscall exec -> 3
3: syscall open -> 3
3: syscall read -> 1023
3: syscall read -> 968
3: syscall read -> 235
3: syscall read -> 0
3: syscall close -> 0

$ trace 32 grep hello README
3: syscall grep -> 1023
3: syscall grep -> 968
3: syscall grep -> 235
3: syscall grep -> 0
```

*TODO 为什么这里的读取值和官方实例不一样*

测试👉： （我嘞个20s啊）

```bash
chenz@Chenzc:~/lab$ sudo python3 grade-lab-syscall trace
make: 'kernel/kernel' is up to date.
== Test trace 32 grep == trace 32 grep: OK (3.3s)
== Test trace all grep == trace all grep: OK (1.1s)
== Test trace nothing == trace nothing: OK (2.0s)
== Test trace children == trace children: OK (20.5s)
```



### Sysinfo

这个lab也是一个功能性的系统调用。获取操作系统中的工作线程数量与空闲内存

需要依次添加修改:

`kernel/kalloc.c`获取空闲内存

```c
uint64 kgetmem(void) {
    uint64 retV = 0;
    struct run* r;
    r = kmem.freelist;
    while (r != (void*)0) {
        retV += PGSIZE;
        r = r->next;
    }
    freemem = retV;
    return retV;
}
```

`kernel/proc.c`获取工作线程数量

```c
uint64 getunusedproc(void){
    uint64 cnt = 0;
    struct proc* p;
    for (p = proc; p < &proc[NPROC]; p ++) {
        if (p->state != UNUSED) {
            cnt++;
        }
    }
    return cnt;
}
```

`kernel/sysinfo.c`ecall函数

```c
uint64 sys_info(void) {
    uint64 info;
    if (argaddr(0, &info) < 0) {
        return -1;
    }
    int iaddr = ssinfo(info);
    return iaddr;
}
```

`kernel/info.c`组装&拷贝返回

```c
int ssinfo(uint64 addr) {
    struct sysinfo s;
    struct proc* p = myproc();

    s.freemem = kgetmem();
    s.nproc = getunusedproc();
    if (s.freemem < 0 || s.nproc < 0) {
        return -1;
    }

    if (copyout(p->pagetable, addr, (char*)&s, sizeof(s)) < 0) {
        return -1;
    }
    return 0;
}
```

*这里的这个kalloc本来是想 维护一个全局变量 然后在kfree和kalloc的时候 加减这个变量值就可以 然后在返回的时候 直接返回*

*但是不知道为什么不行  有莫名其妙的bug 甚至加锁后会死锁？？ 就先这样吧 TODO*

另外 假如是自己开一个新文件写在里面的话 需要将这个文件也一并注册在Makefile中编译（一个c初学者导致的低级bug）

并且也需要像上面trace一样 在系统调用的各个环节都注册函数 在用户空间创建调用接口等

该lab通过以下sh测试 测试结果有

```bash
$ sysinfotest
sysinfotest: start
sysinfotest: OK
$ sysinfotest
sysinfotest: start
sysinfotest: OK
```

