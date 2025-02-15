---
title: mit6.s081 lecture9
date: 2025-02-09 00:40:58
tags: mit6.s081
---

# Lecture9

在进入Lecture9内容前 先复盘一下xv6 Chapter中的内容

## 控制台输入

先用使用者的角度讲起 在输入的时候我们通常是一行行进行输入 即以`\n`或`ctrl + D`进行分界

在xv6中 是通过几个板块进行读取的

首先在程序启动的时候 可以在`kernel/main.c`中看到`consoleinit()`

程序会在这个函数当中配置硬件的参数等信息（其中注册的比特率 数据结构等 都是直接写入寄存器 使硬件按照该规定生效的）

同时此处配置了`consoleread()`和`consolerwrite()`的两个方法

```c
void consoleinit(void) {
    // 初始化锁
    initlock(&cons.lock, "cons");

    // 配置硬件参数
    uartinit();

    // connect read and write system calls
    // to consoleread and consolewrite.
    // 注册读写系统调用用到的方法
    devsw[CONSOLE].read = consoleread;
    devsw[CONSOLE].write = consolewrite;
}
```

此二方法是控制台输入输出的主要入口

```c
int consoleread(int user_dst, uint64 dst, int n) {
    uint target;
    int c;
    char cbuf;

    target = n;
    // 上锁
    acquire(&cons.lock);
    while (n > 0) {
        // wait until interrupt handler has put some
        // input into cons.buffer.
        // 等待直至缓冲区中有值 （当read偏移量等于write偏移量的时候 代表缓冲区为空）
        while (cons.r == cons.w) {
            if (myproc()->killed) {
                // 进程被杀 放锁
                release(&cons.lock);
                return -1;
            }
            // 阻塞 直到在consoleintr()函数中获取到单行字符 将此wakeup
            sleep(&cons.r, &cons.lock);
        }

        // 更新读取的索引 因为上方的循环是轮询查偏移量
        c = cons.buf[cons.r++ % INPUT_BUF];

        // 判断是否ctrl + D
        if (c == C('D')) {  // end-of-file
            // 如果读取的字节数小于预期 消除此次读取行为偏移量
            if (n < target) {
                // Save ^D for next time, to make sure
                // caller gets a 0-byte result.
                cons.r--;
            }
            // 结束读取循环
            break;
        }

        // copy the input byte to the user-space buffer.
        // 复制到用户空间的缓冲区
        cbuf = c;
        if (either_copyout(user_dst, dst, &cbuf, 1) == -1)
            break;

        // dst指用户空间对应的地址
        dst++;
        --n;

        // 按一行行进行读取 如果读到换行符标识此次读取结束 跳转回用户空间调用处
        if (c == '\n') {
            // a whole line has arrived, return to
            // the user-level read().
            break;
        }
    }
    release(&cons.lock);

    return target - n;
}
```

`consolewrite()`方法逻辑大概一致 且更简单 就不打上来了

首先是通过一个while轮询 判断当前的读写偏移量是否一致 若不一致则代表此时有值需要读 下方就是读的逻辑

同时注意此处有一个`sleep` 使当前线程休眠

**稍微理解一下 也就是阻塞住 直至某个地方传输数据过来了 并且`wakeup / notify`当前线程 才会正常的读取数值**

而这个地方就是`consoleintr()`函数

xv6中的设计是 当用户输入每一个字符的时候 都会发出一个中断 

第四章中已经介绍过中断的相关内容 会跳转到陷阱处理程序当中 同时会将中断的原因存储在`scause`寄存器当中。一旦发现中断来自外部设备。会要求一个称为PLIC的硬件单元告诉它哪个设备中断了。如果是UART，`devintr`调用`uartintr`。

```c
// uart中断时 所调用的代码
void uartintr(void) {
    // read and process incoming characters.
    while (1) {
        // 轮询读取值
        int c = uartgetc();
        if (c == -1)
            break;
        // 控制条中断
        consoleintr(c);
    }

    // send buffered characters.
    acquire(&uart_tx_lock);
    uartstart();
    release(&uart_tx_lock);
}
```

然后会在此跳转到`consoleintr()`当中

```c
// 控制台中断处理函数 根据触发中断的字符判断
void consoleintr(int c) {
    acquire(&cons.lock);

    switch (c) {
        ...
        default:
            if (c != 0 && cons.e - cons.r < INPUT_BUF) {
                c = (c == '\r') ? '\n' : c;

                // echo back to the user.
                consputc(c);

                // store for consumption by consoleread().
                cons.buf[cons.e++ % INPUT_BUF] = c;

                if (c == '\n' || c == C('D') || cons.e == cons.r + INPUT_BUF) {
                    // wake up consoleread() if a whole line (or end-of-file)
                    // has arrived.
                    // 读取到当前行末尾 或 文件末尾 唤醒r偏移量
                    cons.w = cons.e;
                    // 上方consoleread中会通过sleep阻塞住 此处松开这个锁
                    // TODO 本质上是单线程内的多程序执行时的 上下文切换调度实现两者间跳转
                    wakeup(&cons.r);
                }
            }
            break;
    }

    release(&cons.lock);
}
```

该中断函数的类型可以理解为是一次预处理 判断该次输入是否控制字符 即`ctrl+c` `ctrl + d`一类

如果不是 会将当前数据塞到缓冲区当中

塞到当行末尾了 或者是文件末尾了就会`wakeup`读取函数`consoleread()`

然后通过`consoleread()` 中的

```c
        if (either_copyout(user_dst, dst, &cbuf, 1) == -1)
```

就可以将读取的值复制回用户空间 进行之后的逻辑处理

总结一下逻辑就是：

- 执行`consoleread()` 在while处阻塞 等待单行值到来

- 待读取数值输入 -> 触发中断 -> 判断中断类型 -> uart硬件读取输入字符 -> `consoleintr()`判断输入值性质 将值加入缓冲区当中 -> 单行值读取成功 `\n`or`ctrl + D` -> 交给`consoleread()`进行读取

- `consoleread()`读取成功 -> 复制回用户空间 -> 单次中断读取结束



写的逻辑本质上也是一样的 但是xv6中的设计 无需等到一行再进行输出 而是每一个字节都通过一次中断进行输出

关键的函数有`consolewrite()`,`uartintr()`,`uartstart()`,`uartputc()`

在执行write调用的时候 会首先跳转到`consolewrite()`，然后会一个个字符调用`uartputc`

```c
void uartputc(int c) {
    acquire(&uart_tx_lock);

    while (1) {
        if (uart_tx_w == uart_tx_r + UART_TX_BUF_SIZE) {
            // 缓冲区满 锁住
            // buffer is full.
            // wait for uartstart() to open up space in the buffer.
            sleep(&uart_tx_r, &uart_tx_lock);
        } else {
            // 将一个字符塞到uart缓冲区当中
            uart_tx_buf[uart_tx_w % UART_TX_BUF_SIZE] = c;
            uart_tx_w += 1;
            // 修改偏移量 输出
            uartstart();
            release(&uart_tx_lock);
            return;
        }
    }
}
```

此处将传进来的这个字符塞到uart缓冲区当中 并且调用了`uartstart()` 

```c
void uartstart() {
    // 判断当前缓存区是否空或满
    while (1) {
        if (uart_tx_w == uart_tx_r) {
            // transmit buffer is empty.
            return;
        }

        if ((ReadReg(LSR) & LSR_TX_IDLE) == 0) {
            // the UART transmit holding register is full,
            // so we cannot give it another byte.
            // it will interrupt when it's ready for a new byte.
            return;
        }

        // 从 UART 传输缓冲区中取出一个字符发送给 UART 控制器
        int c = uart_tx_buf[uart_tx_r % UART_TX_BUF_SIZE];
        uart_tx_r += 1;

        // maybe uartputc() is waiting for space in the buffer.
        // 唤醒线程 等待字符输入缓冲区当中
        wakeup(&uart_tx_r);

        WriteReg(THR, c);
    }
}
```

这个方法的作用就是将这个在缓冲区的字符拿出来 并进行实际的输出（写到UART的发送寄存器当中）

如果之前缓冲区是满的话是sleep的 这里进行wakeup (**条件同步**)

保证正常输出字符



按照上方的原始思路的话 无论是输入还是输出

都是以单个字符为单位进行中断 然后操作的

而中断的代价还是比较大的 从Lab4中已经可以知道了 需要拷贝所有的寄存器 操作后还需要再次恢复现场 回收空间

并且在该方案下 除了中断本身带来的数据 将数据来回从内核空间和用户空间之间复制都是需要一定代价的



所以这样的方案是有待优化的

思路有：

- 批处理 直接以单行为单位进行读取或写入
- DMA 直接内存访问 不再通过UART寄存器进行读取 （UART模式下 单次只能读取单个字节的数据）

- 结合轮询和其他策略一并使用



进入正题

关于中断

某种程度上和系统调用差不多 都需要陷入内核等

两者在执行的时候 都需要拷贝数据 保护现场 

但是两者最基本的区分点有

- 异步性 系统调用的时候 我们是从用户空间调用系统调用的 然后从该处陷入内核空间 整个调用的过程是同步的 均是在运行某一个进程的背景下执行的；但中断可以分为多种情况 可以是由设备产生的 可以是操作系统本身申请的 若非操作系统自己产生 ，可以理解为产生中断的对象与操作系统本**身是异步的** 两者之间并行工作
- 并发性 系统调用的时候 是按照同步原则调用的 与其他线程的工作互不干涉；而中断可以在程序运行的任何一刻产生一个或者多个 这个产生eg可以是在程序运行中时的输入输出中断

- 发起 / 处理中断的外设需要人为编程



输出输出中断：

uart硬件中有对应的输入输出寄存器 接受 / 发送信号 中断由此处产生

PLIC负责管理 / 路由外设中断 将请求发送到某一个空闲的核当中 

（当某个核忙 就会关闭中断 若启用中断 则代表当前为空闲）

同时 中断之间亦有优先级 

内核可以管理先处理哪一个中断 

`plic`中的代码 其实就是调度算法 决定了对于当前的中断 哪一个核来进行处理





驱动 —— 管理设备的代码 xv6中对应着的`uart.c`中的代码

在处理中断的时候 如果此时有多个中断等待处理 会有一个队列来存储

整个处理的过程本质上是一个单线程的调度模型

这个模型的顶部是各种中断 当中段到来的时候 会判断中断的性质 然后路由到对应的驱动程序当中

可以看作是一个生产消费模型 而队列则是解耦双方的 防止数据的覆盖

但是一旦数据太多了 超过了队列的容量 就会导致数据的覆盖

使得CPU和设备之间可以并行运行

在这里称作 `typical driver`

![](/./images/uartkernelfifo.png)





在中断来的时候 我们需要：

关闭中断 （清除`SIE`寄存器中的值）

将当前的程序计数保存下来 (pc -> sepc)

保存当前的操作模式(sstatus)

切换至内核模式

将陷入地址切换到当前pc当中 （pc <- stvec）
