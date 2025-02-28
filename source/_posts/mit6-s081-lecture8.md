---
title: mit6.s081 lecture8
date: 2025-02-06 21:34:58
tags: mit6.s081
---

# Lecture8

在xv6中现有的实现当中，当出现了`pagefault`，会直接`panic`报错，然后杀掉对应的进程

而在实际上的操作系统当中 往往会利用这个产生一个缺页中断 来实现一个 **lazy allocation**的效果

本质上就是通过**标志位 状态变量**等方法 判断此次中断是否需要加载资源的情况

然后捕获该次**异常（中断）** 对资源进行加载即可

**怎么进行判断呢？**

- `stval`：存储出错时的虚拟地址 或访问出错的目标地址 up to具体的错误类型
- `scause`：存储出错的原因 存储，读取异常等
- `sepc`：存储出错时的位置 计数器

以下为`scause`值所对应的具体错误类型：

![scause](/./images/scause.png)

某个角度上就在中断的时候得到了 **哪里出错 为什么出错 谁出错了**



## Lazy

**按需加载**

本质上是一种设计模式 体现在懒汉式单例模式 等等乱七八糟的场景下

定义不赘述



## Lazy Page Allocation

本质上就是动态分配内存，默认的xv6实现的分配内存的模式是`eager`的，也就是在`sbrk()`等指令调用的时候，就立马执行对于大小的内存空间分配与缩小。

但是在实际的使用过程中 由于局部性原理等 应用程序往往不需要用到分配的那么多内存（会预留出一部分的空间）

这样会导致了实际内存的浪费 当同时启动的应用程序越多的时候 这个缺点就越明显

于是我们可以按照**lazy**的思路进行修改

![](/./images/lazysbrk.jpg)

当使用`sbrk()`的时候 修改为仅修改`p-sz`（进程中堆栈之间分界的位置） 

拓展（缩小）当前栈中可以分配的位置 但是部实际分配内存

这样子 当应用程序执行操作的时候 必定会触发异常 我们可以捕获这个异常

结合当前操作所需要的空间大小以及当前的`sz`所指向的位置判断 是否应合法分配空间

如果可以分配的话 就kalloc 然后重新执行对应的函数就可以了

这个过程**是应该对应用程序完全透明的**

free的话 也不影响





## Zero Fill On Demand

这个点指的是 对应用程序中尚未使用到的 未初始化的全局变量 归纳到一起

然后在使用的时候 再触发缺页中断 进而分配零值

![](/./images/zerofillondemand.jpg)

上方为某个应用程序运行时的结构图

text为指令 data为变量 BSS则指的是尚未初始化或初始化值为0的全局变量

按照默认的eager方式 是在程序exec的时候 就将BSS段中的值全部填充为0

而在这一次调优之后 则会在需要的时候 再将程序的值进行初始化 （懒加载 懒初始化值的形式）

为他赋值的话 则正常的为他分配空间 然后修改到data段中即可

这一过程**同样是可以对应用程序透明的**



## COW - Copy On Write

在我们想要执行某个应用程序的时候 是通过`fork()`+ `exec()`实现的

在这个过程中 是将父进程的所有数据都拷贝一份给子进程

但是在执行`exec()`的时候 子进程会将自己变成拷贝所得的应用程序

这种情况下 拷贝所得的父进程相关数据篇又会丢弃

也就是进行了**无效的拷贝** 造成了很大的资源浪费



于是就有了一个优化的思路 在fork子进程的时候 不会复制对应的资源

而是父进程和子进程共享资源 共享fd等数据

这样子就大大减少拷贝的成本 但是会带来一些诸如竞态的问题

![](/./images/copyonwrite.jpg)

一个可行的解决思路是 在fork的时候 将父进程所指向的所有的PTE全部设置为**只读**

这样子 读请求的时候不影响使用

写请求的时候 会先判断当前是**父进程or子进程** 这个可以通过pid 或 PTE中的标志位判断

- 假如是父进程 在写的时候 会触发**pagefault** 然后直接修改当前的页面 并重新设置为只读

- 假如是子进程 同样会触发**pagefault** 但是操作系统可以在此时 分配一个新的 物理内存page

原有的父子共享的页 是同时对两个可见的 所以设置为只读

而子进程经过修改后分配的new page 则是仅对子进程可见的 所以可以将该内存页的PTE设置为可读写

而原只读的对应PTE（使子进程触发pagefault的） 当前也只对父进程可见 此时也可以将他设置为可读写



这是理想状况下的一个调优思路

但是会触发到很多问题：

**假如子进程此时又fork了一个子进程的子进程 此时则会三者共同指向一个PTE当中 怎么办？**

三个或多个本质上是不影响使用的 **只需要修改最后设置为可读写的时机**

修改的时机本质上是指 若当前仅一个指向 就可以修改  —— *有点像垃圾回收*

所以同理也可以使用垃圾回收的思路应对 因为此时没有循环引用的情况会出现 （单方面指向）

所以此时可以使用**引用计数法**来进行判断 设置在内存页的标志位即可

（每个page都预留了两位RSW给管理员模式进行拓展 可以就在此记录）



**假如某些page本身就是只读的 但是在copyOnWrite的场景下 一律只读 这种修改方式不是就会对原来的只读页造成影响吗**

这个问题可以翻译为 如何标记在copyonwrite影响下 变为只读的page

同样可以利用RSW位 记录当前是否RSW位的只读



## Demand Paging & Mmap

这个可能是最为人熟知的内存用法

当我们执行某个程序的时候 xv6此时eager的做法是将整个二进制文件都加载到内存当中

但是有的时候 这个二进制文件可能非常大 甚至可能比物理内存都大 这个时候 eager的方式很明显是行不通的

所以此时的做法就是 利用中断

在发生中断的时候 从磁盘中加载应用程序的所需部分内容

这样就很明细的减轻了内存的压力

**但是仅仅这么做 最后还是会将 整个二进制文件加载进来 占用相当内存吧 怎么办？**

回撤内存 将内存中没有使用到的部分直接回收掉

本质撒谎给你就是分页机制的淘汰机制

淘汰的机制有哪些？ 最经典的就是LRU了

如果读者对数据库原理相关有一定了解的话 可以类比一下MySQL中的`change buffer`

此处的作用机制和操作意义本质上都是差不多的 可以类比来理解一下

`mmap`则是一个**内存——文件之间内容映射**的机制 而**demand paging**则是实现这个设计的一种方式
