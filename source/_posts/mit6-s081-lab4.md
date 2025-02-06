---
title: mit6.s081 lab4
date: 2025-02-02 00:53:20
tags: mit6.s081
---

## RISC-V assembly

这个lab是回答一下问题并记录 此处就直接把问题分析和答案打上来了 答案通过chatGPT查验

`call.asm`中的`g`、`f`、`main`具体的代码

```asm
int g(int x) {
   0:	1141                	addi	sp,sp,-16
   2:	e422                	sd	s0,8(sp)
   4:	0800                	addi	s0,sp,16
  return x+3;
}
   6:	250d                	addiw	a0,a0,3
   8:	6422                	ld	s0,8(sp)
   a:	0141                	addi	sp,sp,16
   c:	8082                	ret

000000000000000e <f>:

int f(int x) {
   e:	1141                	addi	sp,sp,-16
  10:	e422                	sd	s0,8(sp)
  12:	0800                	addi	s0,sp,16
  return g(x);
}
  14:	250d                	addiw	a0,a0,3
  16:	6422                	ld	s0,8(sp)
  18:	0141                	addi	sp,sp,16
  1a:	8082                	ret

000000000000001c <main>:

void main(void) {
  1c:	1141                	addi	sp,sp,-16
  1e:	e406                	sd	ra,8(sp)
  20:	e022                	sd	s0,0(sp)
  22:	0800                	addi	s0,sp,16
  printf("%d %d\n", f(8)+1, 13);
  24:	4635                	li	a2,13
  26:	45b1                	li	a1,12
  28:	00001517          	auipc	a0,0x1
  2c:	80850513          	addi	a0,a0,-2040 # 830 <malloc+0xec>
  30:	00000097          	auipc	ra,0x0
  34:	65c080e7          	jalr	1628(ra) # 68c <printf>
  exit(0);
  38:	4501                	li	a0,0
  3a:	00000097          	auipc	ra,0x0
  3e:	2b8080e7          	jalr	696(ra) # 2f2 <exit>
```

这里涉及到的很多代码可以粗略理解为三个层次

**准备现场 -> 函数调用、执行逻辑 -> 恢复现场**



**准备现场如何做？** 此处以`g`函数为例子

```asm
addi	sp,sp,-16
sd	s0,8(sp)
addi	s0,sp,16
```

这里首先是通过移动SP栈指针 分配了16字节的空间

然后将s0寄存器中值保存到刚刚分配到的空间的基础上 偏移量为8的位置

然后修改s0寄存器中的值 让它之上当前分配的栈的栈顶

```asm
   6:	250d                	addiw	a0,a0,3
```

真正执行计算 RISC-V中 函数传入的值一般都是放在`a0`寄存器当中的 如果不够放的话 依次会放到`a1`、`a2`等寄存器当中

返回值则会放到`a0`寄存器当中

这应该算是RISC-V中约定俗成的一种规范吧

```asm
   8:	6422                	ld	s0,8(sp)
   a:	0141                	addi	sp,sp,16
   c:	8082                	ret
```

这里就是恢复现场并且`ret`跳转的代码了

将从sp中偏移量为8 之前准备现场时保护的值拿出来 重新放回到s0当中

然后重新修改栈指针 回收该函数所使用的空间

最后ret跳转 （具体地址一般在外部跳转这个函数的时候 外部进行设置好 所以这里不用设置）



可以看到`f`函数是直接`return g(x)` 但是汇编中是因为编译器经过了内联优化

没有进行跳转 而是直接将`g`函数中的代码复制了过来

所以这里不再作解释



对于`main`函数 也可以用这种思路进行思考

```asm
  1c:	1141                	addi	sp,sp,-16
  1e:	e406                	sd	ra,8(sp)
  20:	e022                	sd	s0,0(sp)
  22:	0800                	addi	s0,sp,16
```

由于`main`函数是主函数 所以需要同时设置返回时跳转的地址 即保存在`ra`寄存器当中

​	

```asm
  24:	4635                	li	a2,13
  26:	45b1                	li	a1,12
  28:	00001517          	auipc	a0,0x1
  2c:	80850513          	addi	a0,a0,-2040 # 830 <malloc+0xec>
  30:	00000097          	auipc	ra,0x0
  34:	65c080e7          	jalr	1628(ra) # 68c <printf>
```

这里就是将数据进行处理了

对照一下原来的c代码可以发现这里是直接将`f(8)`的值计算了出来 和`13`一起放进了寄存器中 等待调用

这个也是编译器优化的锅 他将`f(8)`这一函数调用的过程省略了 是 **常量折叠**的体现 直接将其中的值由编译器计算出并且代入



要注意调用printf的过程本质上也是一次函数调用 

所以也是需要准备现场的 这里体现在将计算参数放入寄存器当中

通过指针运算 计算出`printf()`函数的实际位置

最后进行跳转



```asm
  38:	4501                	li	a0,0
  3a:	00000097          	auipc	ra,0x0
  3e:	2b8080e7          	jalr	696(ra) # 2f2 <exit>
```

这一个阶段下 是计算已经完成了

由于`printf`或者其他函数调用的返回值都是会存在寄存器`a0`当中的

所以此处需要将他置0 恢复一开始的现场

然后再对指针进行计算 计算出`ret`所跳转的地址

 （此情境下 是从`printf()`函数内部跳转回`main()`函数当中）

跳转回来了 直接执行最后的`exit(0)`指令 跳转到`exit`对应的位置



至此 调用结束



理解了整个流程之后 就很好回答lab上的问题了

1. 

Q: **Which registers contain arguments to functions? For example, which register holds 13 in main's call to `printf`?**
哪些寄存器包含函数的参数？例如，主函数调用 `printf` 时，哪个寄存器保存了 13？

A: 包含参数的寄存器有`a0`、`a1`、`a2`等等... 这里调用`printf`的时候 是`a2`保存了13

```asm
  24:	4635                	li	a2,13
```

2. 

Q: **Where is the call to function `f` in the assembly code for main? Where is the call to `g`? (Hint: the compiler may inline functions.)**
在主程序的汇编代码中，调用函数 `f` 在哪里？调用 `g` 在哪里？（提示：编译器可能会内联函数。）

A: 调用函数按理来说是会在45 47行中间 但是此处编译器优化进行了常量折叠。理论上是在这一块会进行两次嵌套的分配栈空间 依次到`f`、`g`函数中对值进行计算，再依次恢复



3. 

Q: **At what address is the function `printf` located?**
函数 `printf` 位于哪个地址？

A: 在这里 `printf()`具体的地址计算过程是：先将`PC`寄存器和`0x1`进行计算 得出的值存到`a0`当中 然后将`a0`的值减去2040所得到的

**也就是说  它的位置并不是固定的 是通过计算从而动态确定的**



4. 

Q: **What value is in the register `ra` just after the `jalr` to `printf` in `main`?**
在 `main` 中， `jalr` 到 `printf` 之后，寄存器 `ra` 中的值是什么？

A: 上方也已经解释过 跳转到`printf`的过程本质上也是一次调用 同样需要准备现场等步骤 而在执行完毕之后 是会跳转到当前`main`函数下 `jalr`的下一条指令



5. 

*TODO 这玩意半夜有点看不懂*

**Run the following code.**
运行以下代码。

```
	unsigned int i = 0x00646c72;
	printf("H%x Wo%s", 57616, &i);
```

**What is the output? [Here's an ASCII table](http://web.cs.mun.ca/~michael/c/ascii-table.html) that maps bytes to characters.**
这是什么输出？这是一个 ASCII 表，它将字节映射到字符。

**The output depends on that fact that the RISC-V is little-endian. If the RISC-V were instead big-endian what would you set `i` to in order to yield the same output? Would you need to change `57616` to a different value?**
输出取决于 RISC-V 是小端的这个事实。如果 RISC-V 是大端的，你会将 `i` 设置为什么值以产生相同的输出？你需要将 `57616` 改为不同的值吗？

**[Here's a description of little- and big-endian](http://www.webopedia.com/TERM/b/big_endian.html) and [a more whimsical description](http://www.networksorcery.com/enp/ien/ien137.txt).**
这是对小端和大端的描述，以及一个更富有想象力的描述。





---



## Backtrace

该lab为打印程序调用时的堆栈信息 重点在理解`fp`,`sp`,`ra`等概念以及作用

其他部分暂不说明 这里仅解释lab中所需用到的部分

 ![stack-architect](/images/stack_architect.png)

这个是lecture中介绍的栈结构 由于在xv6中 地址是由高到低进行分配的 所以在这里可以和hints中可以观察到

`fp`和`ra`的地址都是需要`fp - offset`这种方式计算出来的

`ra`中存储的即为返回地址 可以通过`*(void *)(sp - 8)`计算得出

`fp`中存储的是**上一个调用者的`sp`地址** 也是我们遍历堆栈所需用到的核心值 （可以类比链表树等的遍历方法思考）

它的值可以通过`*(void *)(sp - 16)`得出



总结一下上面的信息 整个代码的思路就比较清楚了

主要就是构建一个循环（或者递归） 从现有的`sp`计算出`fp`，`ra` 然后基于`fp`进行下一次的遍历

结合hints 以页顶部与底部作为遍历边界值 超过值默认终止循环



从`kernel/printf.c`中改起

```c
void backtrace(void) {
    printf("backtrace:\n");
    
    // 获取当前栈内的fp （上一个调用者栈内的栈指针）
    uint64 fp = r_fp();
    uint64 bottom = PGROUNDDOWN(fp);
    uint64 top = PGROUNDUP(fp);

    //超出当前栈默认遍历完毕
    // 具体可参见xv6中的栈结构 fp中存储的是上一个调用者的指针位置 类比链表树
    // 所以可以直接通过这个fp索引并且打印调用链
    while (fp >= bottom && fp < top) {
        printf("%p\n",  *(uint64*)(fp - 8));
        fp = *(uint64*)(fp - 16);
    }
    return;
}
```

其他就不需要改什么了

`sysproc.c`

```c
uint64 sys_sleep(void) {
	...
    backtrace();
    return 0;
}
```

`riscv.h`

```c
// read value in s0 (which storage the stack frame pointer)
// 读取当前的帧指针并且返回
static inline uint64 r_fp() {
    uint64 x;
    asm volatile("mv %0, s0" : "=r"(x));
    return x;
}
```

`defs.h`

```c
// printf.c
void backtrace(void);
...
```

测试和脚本运行效果👉：

```sh
$ bttest
backtrace:
0x0000000080002524
0x0000000080002356
0x0000000080002044
$ QEMU: Terminated
chenz@Chenzc:~/lab$ addr2line -e kernel/kernel
0x0000000080002524
/home/chenz/lab/kernel/sysproc.c:64
0x0000000080002356
/home/chenz/lab/kernel/syscall.c:143
0x0000000080002044
/home/chenz/lab/kernel/trap.c:80
```

注意 验证方式是将自己通过运行`bttest`得到的`va`通过`add2line`进行验证... 可能会与官方存在些许不同

```sh
chenz@Chenzc:~/lab$ sudo python3 grade-lab-traps backtrace
make: 'kernel/kernel' is up to date.
== Test backtrace test == backtrace test: OK (3.0s)
```



## Alarm

该部分的大致意思就是 实现一个计数器 记录定时器中断发生的次数 并且在触发一定次数后 执行回调函数

**即提供一个可以注册回调函数 以及触发调用条件的API**

Lab上分为`test0`和`test1/2` 这里也分开介绍 两者的思路本质上是一致的

### test0

这部分就是单纯完成`sys_sigalarm()`函数

注册系统调用 调用流程上`syscall.c syscall.h usys.pl user.h Makefile`中也需要注册对应 这里不再赘述

 完成的思路其实可以参照`trace()`的完成步骤 在`proc.h`中新增包含对应流转信息的字段、结构体

然后`allocproc()`中分配空间 当调用该系统调用`sys_sigalarm()`的时候 注册对应的条件

在定时器中断的分支语句下 累计中断刻度次数 并且判断是否符合回调条件即可



`proc.h`

```c
struct sigcontext {
    int alramtick; // demanded alram ticks. 调用时机（触发调用的刻度数）
    int ticks;  // ticks after last sigalarm. 自上次警告处理器过去 已经过去了多少个刻度
    uint64 handler;  // func exec when alarm. sigalarm 的时候执行的函数
};
// Per-process state
struct proc {
	...
	struct sigcontext sigcontext;
};
```

`sysproc.c`

```c
// 注册传入的sigalarm函数
uint64 sys_sigalarm(void) {
    int ticks;
    uint64 hp;
    if (argint(0, &ticks) < 0 || argaddr(1, &hp)) {
        return -1;
    }
    struct proc* p = myproc();
    p->sigcontext.alramtick = ticks;
    p->sigcontext.ticks = 0;
    p->sigcontext.handler = hp;
    return 0;
}

// test0中只需return0
uint64 sys_sigreturn(void) {
    return 0;
}
```

`proc.c`

```c
static struct proc* allocproc(void) {
    struct proc* p;
    ...

found:
    ...
        
    // 为alarm函数分配空间
    memset(&p->sigcontext, 0, sizeof(p->sigcontext));
    p->sigcontext.alramtick = 0;
    p->sigcontext.ticks = 0;
    p->sigcontext.handler = 0;

    return p;
}
```

上述步骤 完成了初始化 存储调用条件和函数指针的阶段

还差最关键的 **何时触发？**

从hints中可以知道关键点在`trap.c`中的`usertrap()`函数当中 此处仅保留有用信息

```c
void usertrap(void) {
    int which_dev = 0;
    struct proc* p = myproc();
    // 保存用户空间当前执行的进度（栈顶）
    p->trapframe->epc = r_sepc();
	...
        
    if (r_scause() == 8) {
		...        
    } else if ((which_dev = devintr()) != 0) {
        // ok
    } else {
        ...
    }

    // give up the CPU if this is a timer interrupt.
    // 定时片花完了 主动让出CPU
    if (which_dev == 2) {
        struct sigcontext* sigctx = &p->sigcontext;
        sigctx->ticks++;
        if (sigctx->ticks % sigctx->alramtick == 0) {
            p->trapframe->epc = sigctx->handler; 
        }
        yield();
    }
    usertrapret();
}

```

关键点主要是理解了这个`which_dev`的作用：当前中断的类型 当他为`2`的时候 就代表着定时器中断 所以需要`yield()`——主动让出当前的线程资源

我们的目的是在定时器中断触发的时候 累加当前的刻度数

于是就可以在`if(which_dev == 2)`的分支语句上做手脚 具体的逻辑语句也还都挺简单

重点是将`p.trapframe.epc`中的值赋值为`p.sigctx.handler`

这里的`handler`虽然是本质上是回调函数 但是它是以`uint64`的指针形式传进来的

并且传进来的值 是对应函数的**栈顶** (stack frame)

于是就可以通过设置的方式 进行注册  然后再通过下方`usertrapret()`达成一个 跳转到alarm函数的效果

但是这个`epc`是当前 栈的运行情况啊 怎么能丢呢

我也是这么想的 接下来看`test1/test2`中的修改吧

（先放一下`test0`的脚本测试结果）

```c
$ alarmtest
test0 start
............alarm!
test0 passed
test1 start
..alarm!
.alarm!
.QEMU: Terminated
```

可以看到 由于丢了`epc`原来的值 就没法正常停止`alarmtest`的运行了 会一直循环输出



### test1/test2

*这一部分修改了`sigcontext`按地址传递 并加上了`inalarm`的变量 这些修改不是lab所考察的 并且不影响代码结果 对应具体修改可以在`traps`分支下查看具体代码*

于是这俩测试就是完成`sigreturn()`系统调用函数。将包括`epc`在内的寄存器信息保存下来，并且在完成陷入之后将保存了的信息恢复出来。

问题就是 **要存哪些寄存器信息？ 在什么时机保存？在什么时机恢复？**

- **什么时机保存？**

问题是 如何在发生陷入的时候 保存数据

**明确陷入的类型、alarm函数的调用**满足两个前提下的只有`usertrap()`函数下的`if(which_dev == 2)`的前提

`trap.c`

```c
    // give up the CPU if this is a timer interrupt.
    // 定时片花完了 主动让出CPU
    if ((which_dev == 2) && (p->inalarm == 0)) {
        struct sigcontext* sigctx = p->sigcontext;
        if (p->sigcontext != 0) {
            sigctx->ticks += 1;

            // 判断是否满足回调条件
            if (sigctx->alramtick != 0 && sigctx->ticks &&
                sigctx->ticks == sigctx->alramtick) {
                // 进入alarm函数内 清空计数器
                p->inalarm = 1;
                sigctx->ticks = 0;
                // 保存寄存器中函数状态
                saving_userregister(p);
                // 存储epc的值
                p->epc = p->trapframe->epc;
                // 修改 执行alarm函数
                p->trapframe->epc = sigctx->handler;
            }
        }
        yield();
    }
```

主要就是这三行的改动 具体的方法体在下方存储结构后给出

```c
                saving_userregister(p);
                // 存储epc的值
                p->epc = p->trapframe->epc;
                // 修改 执行alarm函数
                p->trapframe->epc = sigctx->handler;
```






- **存哪些？**

这个陷入本质上和从用户空间陷入内核空间是同理的

所以我们可以效仿已有陷入时的保存语句 具体可以有下面的字段

`proc.h`

```c
struct sigregister {
    /*  40 */ uint64 ra;
    /*  48 */ uint64 sp;
    /*  56 */ uint64 gp;
    /*  64 */ uint64 tp;
    /*  72 */ uint64 t0;
    /*  80 */ uint64 t1;
    /*  88 */ uint64 t2;
    /*  96 */ uint64 s0;
    /* 104 */ uint64 s1;
    /* 112 */ uint64 a0;
    /* 120 */ uint64 a1;
    /* 128 */ uint64 a2;
    /* 136 */ uint64 a3;
    /* 144 */ uint64 a4;
    /* 152 */ uint64 a5;
    /* 160 */ uint64 a6;
    /* 168 */ uint64 a7;
    /* 176 */ uint64 s2;
    /* 184 */ uint64 s3;
    /* 192 */ uint64 s4;
    /* 200 */ uint64 s5;
    /* 208 */ uint64 s6;
    /* 216 */ uint64 s7;
    /* 224 */ uint64 s8;
    /* 232 */ uint64 s9;
    /* 240 */ uint64 s10;
    /* 248 */ uint64 s11;
    /* 256 */ uint64 t3;
    /* 264 */ uint64 t4;
    /* 272 */ uint64 t5;
    /* 280 */ uint64 t6;
};
```

将此字段加入线程结构体中 （以线程为颗粒度记录`alarm`时保存的信息）

`proc.h`

```c
// Per-process state
struct proc {
   	...
    struct sigregister sigregister; // save user program counter.
    uint64 epc;   // cache pc container when using alarm.
    int inalarm;  // clarify if it is alraming func.
};
```

按照对应字段依次"入栈"存储 就有了具体的`saving_userregister()`函数

`trap.c`

```c
void saving_userregister(struct proc* p) {
    struct sigregister* s = &p->sigregister;
    struct trapframe* t = p->trapframe;
    s->ra = t->ra;
    s->sp = t->sp;
    s->gp = t->gp;
    s->tp = t->tp;
    s->t0 = t->t0;
    s->t1 = t->t1;
    s->t2 = t->t2;
    s->s0 = t->s0;
    s->s1 = t->s1;
    s->a0 = t->a0;
    s->a1 = t->a1;
    s->a2 = t->a2;
    s->a3 = t->a3;
    s->a4 = t->a4;
    s->a5 = t->a5;
    s->a6 = t->a6;
    s->a7 = t->a7;
    s->s2 = t->s2;
    s->s3 = t->s3;
    s->s4 = t->s4;
    s->s5 = t->s5;
    s->s6 = t->s6;
    s->s7 = t->s7;
    s->s8 = t->s8;
    s->s9 = t->s9;
    s->s10 = t->s10;
    s->s11 = t->s11;
    s->t3 = t->t3;
    s->t4 = t->t4;
    s->t5 = t->t5;
    s->t6 = t->t6;
}
```





- **在什么时机恢复？**

`alarmtest.c`

```c
void periodic() {
    count = count + 1;
    printf("alarm!\n");
    sigreturn();
}
```

查看`alarmtest()`中的测试用例  可知`sigreturn`是在`alarm`函数调用后恢复现场的

Obviously 对应的恢复load寄存器代码就写在这玩意里

`sysproc.c`


```c
uint64 sys_sigreturn(void) {
    struct proc* p = myproc();
    // 恢复现场
    load_userregister(p);
    p->trapframe->epc = p->epc;
    p->inalarm = 0;
    return 0;
}
```

`proc.c`

```c
void load_userregister(struct proc* p) {
    struct sigregister* s = &p->sigregister;
    struct trapframe* t = p->trapframe;

    t->ra = s->ra;
    t->sp = s->sp;
    t->gp = s->gp;
    t->tp = s->tp;
    t->t0 = s->t0;
    t->t1 = s->t1;
    t->t2 = s->t2;
    t->s0 = s->s0;
    t->s1 = s->s1;
    t->a0 = s->a0;
    t->a1 = s->a1;
    t->a2 = s->a2;
    t->a3 = s->a3;
    t->a4 = s->a4;
    t->a5 = s->a5;
    t->a6 = s->a6;
    t->a7 = s->a7;
    t->s2 = s->s2;
    t->s3 = s->s3;
    t->s4 = s->s4;
    t->s5 = s->s5;
    t->s6 = s->s6;
    t->s7 = s->s7;
    t->s8 = s->s8;
    t->s9 = s->s9;
    t->s10 = s->s10;
    t->s11 = s->s11;
    t->t3 = s->t3;
    t->t4 = s->t4;
    t->t5 = s->t5;
    t->t6 = s->t6;

    return;
}
```

写的时候出现了很多小问题 但是摊出来没多少东西 感觉还是得重新学下gdb 不是很会调试

测试脚本和运行程序结果：

```sh
$ alarmtest
test0 start
......alarm!
test0 passed
test1 start
.alarm!
.alarm!
..alarm!
..alarm!
.alarm!
.alarm!
.alarm!
.alarm!
.alarm!
..alarm!
test1 passed
test2 start
..........alarm!
test2 passed
```

```sh
chenz@Chenzc:~/lab$ sudo python3 grade-lab-traps alarm
make: 'kernel/kernel' is up to date.
== Test running alarmtest == (8.0s)
== Test   alarmtest: test0 ==
  alarmtest: test0: OK
== Test   alarmtest: test1 ==
  alarmtest: test1: OK
== Test   alarmtest: test2 ==
  alarmtest: test2: OK
```
